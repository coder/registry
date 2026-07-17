#!/usr/bin/env bun
/**
 * Builds (or updates) the pinned index discussion listing every module
 * scorecard with per-theme scores, grouped by track. Results are read back
 * from the module scorecard discussions, so partial scoring runs still
 * produce a complete index.
 *
 * Env (required):
 *   GITHUB_DISCUSSIONS_TOKEN  GitHub PAT with Discussions read/write
 *
 * Usage:
 *   bun run scorecard-index.ts [--dry-run]
 */

import {
  CATEGORY_ID,
  INDEX_MARKER,
  INDEX_TITLE,
  MARKER,
  REPO_ID,
  type Result,
  findDiscussionByTitle,
  graphql,
  parseSummary,
} from "./lib";

interface Args {
  dryRun: boolean;
}

function parseArgs(): Args {
  const args: Args = { dryRun: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case "--dry-run":
        args.dryRun = true;
        break;
      default:
        console.error(`Unknown argument: ${argv[i]}`);
        process.exit(1);
    }
  }
  return args;
}

async function fetchResults(): Promise<Record<string, Result>> {
  const results: Record<string, Result> = {};
  let cursor: string | null = null;
  for (;;) {
    const data: {
      repository: {
        discussions: {
          pageInfo: { hasNextPage: boolean; endCursor: string };
          nodes: { title: string; url: string; body: string }[];
        };
      };
    } = await graphql(
      `query($cursor: String) {
        repository(owner: "coder", name: "registry") {
          discussions(first: 100, after: $cursor, categoryId: "${CATEGORY_ID}") {
            pageInfo { hasNextPage endCursor }
            nodes { title url body }
          }
        }
      }`,
      { cursor },
    );
    for (const d of data.repository.discussions.nodes) {
      if (!d.body.includes(MARKER) || d.body.includes(INDEX_MARKER)) continue;
      const summary = parseSummary(d.body);
      const module = d.body.match(
        /registry\.coder\.com\/modules\/coder\/([a-z0-9-]+)/,
      )?.[1];
      if (!summary || !module) {
        console.error(`warn: could not parse "${d.title}"`);
        continue;
      }
      results[module] = {
        ...summary,
        module,
        name: d.title.replace(/ module$/, ""),
        url: d.url,
        scoredAt: new Date().toISOString(),
      };
    }
    if (!data.repository.discussions.pageInfo.hasNextPage) break;
    cursor = data.repository.discussions.pageInfo.endCursor;
  }
  return results;
}

function buildBody(results: Record<string, Result>): string {
  const rank = (a: Result, b: Result) => b.overallNum - a.overallNum;

  const section = (
    title: string,
    blurb: string,
    rows: Result[],
    withIntegration: boolean,
  ): string => {
    if (rows.length === 0) return "";
    const integrationHeader = withIntegration ? ` ${title} Integration |` : "";
    const integrationSep = withIntegration ? "---:|" : "";
    const body = rows
      .sort(rank)
      .map((r) => {
        const integration = withIntegration ? ` ${r.integration} |` : "";
        return `| [${r.name}](${r.url}) | ${r.presentation} |${integration} ${r.credential} | ${r.network} | ${r.engineering} | **${r.overall}** |`;
      })
      .join("\n");
    return `### ${title} modules

${blurb}

| Module | Presentation & Onboarding |${integrationHeader} Credential Hygiene | Restricted-Environment | Engineering Quality | Overall |
|---|---:|${integrationSep}---:|---:|---:|---:|
${body}
`;
  };

  const all = Object.values(results);
  const sections = [
    section(
      "Agent",
      "AI coding agents you can run in a workspace.",
      all.filter((r) => r.track === "Agent"),
      true,
    ),
    section(
      "IDE",
      "Editors and IDEs users open from the dashboard.",
      all.filter((r) => r.track === "IDE"),
      true,
    ),
    section(
      "Utility",
      "Auth, regions, git helpers, and other workspace plumbing. Scored on the universal themes only, normalized to 100.",
      all.filter((r) => r.track === "Utility"),
      false,
    ),
  ]
    .filter(Boolean)
    .join("\n");

  const now = new Date().toISOString().slice(0, 10);
  return `Every module in the \`coder\` namespace gets a scorecard: a 0-100 score for how well it covers the things we care about in a module, like clear configuration examples, secret handling, air-gapped installs, tests, and Coder platform integration. Each module below links to a dedicated discussion where its scorecard lives and where you can leave thoughts, questions, and feedback.

We built this to have a shared definition of quality for modules. Anyone contributing can see what a good module looks like in one place instead of rediscovering it in review. It is not a gate today (it may become one), and the criteria will change over time. It also catches regressions: modules are re-scored when they change, so a removed feature or deleted doc shows up as a dropped score.

Scores come from Claude reading each module's code, tests, and README against [SCORECARD.md](https://github.com/coder/registry/blob/main/.github/scorecard/SCORECARD.md), with calibration rules to keep it strict and totals computed by script. A GitHub Action re-scores a module when it changes on \`main\`, re-scores everything weekly or when the criteria change, and comments on PRs that would move a module's score. The scores are advisory. If one looks wrong, say so in the module's discussion.

**Want to contribute?** Low scores are a ready-made backlog. Pick a module, open its discussion to see exactly which criteria it misses (a visual preview, air-gapped install docs, tests, session persistence), and open a PR against [\`registry/coder/modules/<module>\`](https://github.com/coder/registry/tree/main/registry/coder/modules).

${sections}
**Notes**: N/A means the theme does not apply to that module (for example, a module that downloads nothing has no install URL to mirror) and is excluded from its total.

---
Updated ${now}. Scores refresh when modules change.
${INDEX_MARKER}`;
}

async function upsertIndex(body: string): Promise<string> {
  const existing = await findDiscussionByTitle(INDEX_TITLE);
  if (existing) {
    await graphql(
      `
        mutation ($id: ID!, $body: String!) {
          updateDiscussion(input: { discussionId: $id, body: $body }) {
            discussion {
              id
            }
          }
        }
      `,
      { id: existing.id, body },
    );
    return existing.url;
  }
  const created = await graphql<{
    createDiscussion: { discussion: { url: string } };
  }>(
    `
      mutation ($repoId: ID!, $catId: ID!, $title: String!, $body: String!) {
        createDiscussion(
          input: {
            repositoryId: $repoId
            categoryId: $catId
            title: $title
            body: $body
          }
        ) {
          discussion {
            url
          }
        }
      }
    `,
    { repoId: REPO_ID, catId: CATEGORY_ID, title: INDEX_TITLE, body },
  );
  return created.createDiscussion.discussion.url;
}

async function main() {
  const args = parseArgs();
  if (!process.env.GITHUB_DISCUSSIONS_TOKEN) {
    throw new Error("GITHUB_DISCUSSIONS_TOKEN not set");
  }
  const results = await fetchResults();
  console.error(`found ${Object.keys(results).length} module scorecards`);
  const body = buildBody(results);
  if (args.dryRun) {
    console.log(body);
    return;
  }
  const url = await upsertIndex(body);
  console.error(`index: ${url}`);
}

main();
