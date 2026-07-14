#!/usr/bin/env bun
/**
 * Builds (or updates) the pinned index discussion listing every module
 * scorecard with per-theme scores, from local results written by
 * score-modules.ts (.scorecard-results.json).
 *
 * Env (required):
 *   GITHUB_DISCUSSIONS_TOKEN  GitHub PAT with Discussions read/write
 *
 * Usage:
 *   bun run scorecard-index.ts [--dry-run] [--downloads downloads.json] [--from-github]
 *
 * --from-github: one-time backfill of .scorecard-results.json from existing
 *   discussions (for runs made before local result tracking existed).
 * downloads.json (optional): {"claude-code": 12345, ...} module dir -> count.
 * When provided, the table is ranked by downloads; otherwise by overall score.
 */

import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const RESULTS_PATH = path.join(import.meta.dir, ".scorecard-results.json");

const REPO_ID = "R_kgDOOVbRAA"; // coder/registry
const CATEGORY_ID = "DIC_kwDOOVbRAM4DBMLT"; // "Modules"
const MARKER = "<!-- module-scorecard -->";
const INDEX_MARKER = "<!-- module-scorecard-index -->";
const INDEX_TITLE = "📊 Module Scorecards";

interface Result {
  module: string;
  name: string;
  url: string;
  scoredAt: string;
  track: "Agent" | "IDE" | "Utility";
  presentation: string;
  integration: string;
  credential: string;
  network: string;
  engineering: string;
  overall: string;
  overallNum: number;
}

interface Args {
  dryRun: boolean;
  downloadsPath?: string;
  fromGithub: boolean;
}

function parseArgs(): Args {
  const args: Args = { dryRun: false, fromGithub: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--downloads":
        args.downloadsPath = argv[++i];
        break;
      case "--from-github":
        args.fromGithub = true;
        break;
      default:
        console.error(`Unknown argument: ${argv[i]}`);
        process.exit(1);
    }
  }
  return args;
}

async function graphql<T>(
  query: string,
  variables: Record<string, unknown> = {},
): Promise<T> {
  const res = await fetch("https://api.github.com/graphql", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.GITHUB_DISCUSSIONS_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });
  const body = (await res.json()) as { data?: T; errors?: unknown[] };
  if (!res.ok || body.errors?.length) {
    throw new Error(
      `GitHub GraphQL error: ${JSON.stringify(body.errors ?? body)}`,
    );
  }
  return body.data!;
}

function parseSummaryFromBody(
  title: string,
  url: string,
  body: string,
): Result | null {
  const dirMatch = body.match(
    /registry\.coder\.com\/modules\/coder\/([a-z0-9-]+)/,
  );
  const lines = body.split("\n");
  const headerIdx = lines.findIndex(
    (l) =>
      l.startsWith("|") && l.includes("Overall") && l.includes("Presentation"),
  );
  if (headerIdx === -1) return null;
  const headers = lines[headerIdx]
    .split("|")
    .map((c) => c.trim())
    .filter(Boolean);
  const cells = lines[headerIdx + 2]
    ?.split("|")
    .map((c) => c.trim().replace(/\*\*/g, ""))
    .filter(Boolean);
  if (!cells || cells.length !== headers.length) return null;
  const get = (name: string) => {
    const i = headers.findIndex((h) => h.toLowerCase().includes(name));
    return i === -1 ? "—" : cells[i];
  };
  const integrationIdx = headers.findIndex((h) => /integration/i.test(h));
  const track: Result["track"] =
    integrationIdx === -1
      ? "Utility"
      : /agent/i.test(headers[integrationIdx])
        ? "Agent"
        : "IDE";
  const overall = get("overall");
  return {
    module: dirMatch?.[1] ?? "",
    name: title.replace(/ module$/, ""),
    url,
    scoredAt: new Date().toISOString(),
    track,
    presentation: get("presentation"),
    integration: integrationIdx === -1 ? "—" : cells[integrationIdx],
    credential: get("credential"),
    network: get("restricted"),
    engineering: get("engineering"),
    overall,
    overallNum: Number(overall.match(/(\d+)\s*\/\s*100/)?.[1] ?? 0),
  };
}

async function backfillFromGithub(): Promise<Record<string, Result>> {
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
      const r = parseSummaryFromBody(d.title, d.url, d.body);
      if (r?.module) results[r.module] = r;
      else console.error(`warn: could not parse "${d.title}"`);
    }
    if (!data.repository.discussions.pageInfo.hasNextPage) break;
    cursor = data.repository.discussions.pageInfo.endCursor;
  }
  await Bun.write(RESULTS_PATH, JSON.stringify(results, null, 2) + "\n");
  console.error(
    `backfilled ${Object.keys(results).length} results to ${RESULTS_PATH}`,
  );
  return results;
}

function buildBody(
  results: Record<string, Result>,
  downloads?: Record<string, number>,
): string {
  const rank = (a: Result, b: Result) => {
    if (downloads) {
      const da = downloads[a.module] ?? 0;
      const db = downloads[b.module] ?? 0;
      if (db !== da) return db - da;
    }
    return b.overallNum - a.overallNum;
  };

  const dlHeader = downloads ? " Downloads |" : "";
  const dlSep = downloads ? "---:|" : "";

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
        const dl = downloads
          ? ` ${(downloads[r.module] ?? 0).toLocaleString()} |`
          : "";
        const integration = withIntegration ? ` ${r.integration} |` : "";
        return `| [${r.name}](${r.url}) |${dl} ${r.presentation} |${integration} ${r.credential} | ${r.network} | ${r.engineering} | **${r.overall}** |`;
      })
      .join("\n");
    return `### ${title} modules

${blurb}

| Module |${dlHeader} Presentation & Onboarding |${integrationHeader} Credential Hygiene | Restricted-Network | Engineering Quality | Overall |
|---|${dlSep}---:|${integrationSep}---:|---:|---:|---:|
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
  return `Every module in the \`coder\` namespace, scored against [SCORECARD.md](https://github.com/coder/registry/blob/main/.github/scorecard/SCORECARD.md). Each module links to its dedicated discussion, where you can share thoughts, questions, and feedback.

**Looking for a way to contribute?** Low scores are contribution opportunities. Pick a module, open its discussion to see exactly which criteria it misses (visual previews, air-gapped install docs, tests, session persistence, and so on), and open a PR against [\`registry/coder/modules/<module>\`](https://github.com/coder/registry/tree/main/registry/coder/modules).

${sections}
**Notes**: N/A means the theme does not apply by construction and is excluded from the denominator.

---
Updated ${now}. Scores refresh when modules change.
${INDEX_MARKER}`;
}

async function upsertIndex(body: string): Promise<string> {
  const data = await graphql<{
    search: { nodes: { id: string; title: string; url: string }[] };
  }>(
    `
      query ($q: String!) {
        search(query: $q, type: DISCUSSION, first: 10) {
          nodes {
            ... on Discussion {
              id
              title
              url
            }
          }
        }
      }
    `,
    { q: `"${INDEX_TITLE}" in:title repo:coder/registry` },
  );
  const existing = data.search.nodes.find((n) => n.title === INDEX_TITLE);
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
  let results: Record<string, Result>;
  if (args.fromGithub) {
    results = await backfillFromGithub();
  } else {
    if (!existsSync(RESULTS_PATH)) {
      throw new Error(
        `${RESULTS_PATH} not found. Run score-modules.ts first, or use --from-github to backfill.`,
      );
    }
    results = JSON.parse(await readFile(RESULTS_PATH, "utf8"));
  }
  let downloads: Record<string, number> | undefined;
  if (args.downloadsPath) {
    downloads = JSON.parse(await readFile(args.downloadsPath, "utf8"));
  }
  const body = buildBody(results, downloads);
  if (args.dryRun) {
    console.log(body);
    return;
  }
  const url = await upsertIndex(body);
  console.error(`index: ${url}`);
}

main();
