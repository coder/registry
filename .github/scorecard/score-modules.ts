#!/usr/bin/env bun
/**
 * Scores Coder Registry modules against SCORECARD.md using Claude, then
 * posts (or updates) one GitHub Discussion per module in coder/registry.
 *
 * Env (required):
 *   ANTHROPIC_API_KEY         Anthropic API key
 *   GITHUB_DISCUSSIONS_TOKEN  GitHub PAT with Discussions read/write
 *
 * Usage:
 *   bun run score-modules.ts [--modules a,b,c] [--dry-run] [--limit N]
 *
 * --dry-run prints scorecards to stdout and skips GitHub entirely.
 */

import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const REGISTRY_ROOT = path.resolve(import.meta.dir, "..", "..");
const MODULES_DIR = path.join(REGISTRY_ROOT, "registry", "coder", "modules");
const SCORECARD_PATH = path.join(import.meta.dir, "SCORECARD.md");

const REPO_ID = "R_kgDOOVbRAA"; // coder/registry
const CATEGORY_ID = "DIC_kwDOOVbRAM4DBMLT"; // "Modules" category
const REPO_OWNER = "coder";
const REPO_NAME = "registry";

const ANTHROPIC_MODEL = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5";
const MAX_FILE_BYTES = 30_000;

const MARKER = "<!-- module-scorecard -->";
const RESULTS_PATH = path.join(import.meta.dir, ".scorecard-results.json");

interface SummaryScores {
  track: "Agent" | "IDE" | "Utility";
  presentation: string;
  integration: string;
  credential: string;
  network: string;
  engineering: string;
  overall: string;
  overallNum: number;
}

interface Result extends SummaryScores {
  module: string;
  name: string;
  url: string;
  scoredAt: string;
}

function parseSummary(scorecard: string): SummaryScores | null {
  const lines = scorecard.split("\n");
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
    return i === -1 ? "\u2014" : cells[i];
  };
  const integrationIdx = headers.findIndex((h) => /integration/i.test(h));
  const track: SummaryScores["track"] =
    integrationIdx === -1
      ? "Utility"
      : /agent/i.test(headers[integrationIdx])
        ? "Agent"
        : "IDE";
  const overall = get("overall");
  return {
    track,
    presentation: get("presentation"),
    integration: integrationIdx === -1 ? "\u2014" : cells[integrationIdx],
    credential: get("credential"),
    network: get("restricted"),
    engineering: get("engineering"),
    overall,
    overallNum: Number(overall.match(/(\d+)\s*\/\s*100/)?.[1] ?? 0),
  };
}

async function saveResult(result: Result): Promise<void> {
  let results: Record<string, Result> = {};
  if (existsSync(RESULTS_PATH)) {
    results = JSON.parse(await readFile(RESULTS_PATH, "utf8"));
  }
  results[result.module] = result;
  await Bun.write(RESULTS_PATH, JSON.stringify(results, null, 2) + "\n");
}

async function displayName(moduleName: string): Promise<string> {
  const readme = await readFile(
    path.join(MODULES_DIR, moduleName, "README.md"),
    "utf8",
  );
  const match = readme.match(/^display_name:\s*["']?([^"'\n]+)["']?\s*$/m);
  return match ? match[1].trim() : moduleName;
}

interface Args {
  modules?: string[];
  dryRun: boolean;
  limit?: number;
}

function parseArgs(): Args {
  const args: Args = { dryRun: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case "--modules":
        args.modules = argv[++i].split(",").map((s) => s.trim());
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--limit":
        args.limit = Number(argv[++i]);
        break;
      default:
        console.error(`Unknown argument: ${argv[i]}`);
        process.exit(1);
    }
  }
  return args;
}

async function readTruncated(filePath: string): Promise<string> {
  const content = await readFile(filePath, "utf8");
  if (content.length <= MAX_FILE_BYTES) return content;
  return content.slice(0, MAX_FILE_BYTES) + "\n... [truncated]";
}

async function gatherModuleContext(moduleName: string): Promise<string> {
  const dir = path.join(MODULES_DIR, moduleName);
  const parts: string[] = [];
  const files = await readdir(dir, { recursive: true });
  const wanted = files.filter(
    (f) =>
      typeof f === "string" &&
      (f.endsWith(".md") ||
        f.endsWith(".tf") ||
        f.endsWith(".tftest.hcl") ||
        f.endsWith(".test.ts") ||
        f.endsWith(".sh") ||
        f.endsWith(".tftpl")),
  ) as string[];
  for (const f of wanted.sort()) {
    const full = path.join(dir, f);
    parts.push(`=== FILE: ${f} ===\n${await readTruncated(full)}`);
  }
  return parts.join("\n\n");
}

function fixOverall(scorecard: string): string {
  // Find the summary table's data row: first row whose cells are bold
  // "**a / b**" fractions (or N/A), ending with the overall cell.
  const lines = scorecard.split("\n");
  const rowIdx = lines.findIndex(
    (l) => /^\|\s*\*\*\d/.test(l.trim()) && l.includes("/ 100"),
  );
  if (rowIdx === -1) return scorecard;
  const cells = lines[rowIdx]
    .split("|")
    .map((c) => c.trim())
    .filter((c) => c !== "");
  const themeCells = cells.slice(0, -1);
  let raw = 0;
  let denom = 0;
  for (const cell of themeCells) {
    if (/n\/a/i.test(cell)) continue;
    const m = cell.match(/(\d+(?:\.\d+)?)\s*\/\s*(\d+)/);
    if (!m) return scorecard; // unexpected cell, leave untouched
    raw += Number(m[1]);
    denom += Number(m[2]);
  }
  if (denom === 0) return scorecard;
  const overall = Math.round((raw / denom) * 100);
  cells[cells.length - 1] = `**${overall} / 100**`;
  lines[rowIdx] = `| ${cells.join(" | ")} |`;
  let out = lines.join("\n");
  out = out.replace(
    /#### Overall — \d+(?:\.\d+)? \/ 100/g,
    `#### Overall — ${overall} / 100`,
  );
  // Rewrite or append the normalization line under the Overall heading.
  const normLine =
    denom === 100
      ? ""
      : `\n\nRaw ${raw} / ${denom} → round(${raw} / ${denom} × 100) = **${overall}**`;
  out = out.replace(/\n+Raw \d+(?:\.\d+)?\s*\/\s*\d+[^\n]*/g, "");
  out = out.replace(
    new RegExp(`(#### Overall — ${overall} / 100)`),
    `$1${normLine}`,
  );
  return out;
}

async function scoreModule(
  moduleName: string,
  rubric: string,
): Promise<string> {
  const context = await gatherModuleContext(moduleName);
  const prompt = `You are scoring a Coder Registry module against a scorecard rubric.

<rubric>
${rubric}
</rubric>

<module name="coder/${moduleName}">
${context}
</module>

Score the module strictly against the rubric. Rules:
- First decide the track: Agent, IDE, or Utility. Agent = AI coding agents (CLI agents like Claude Code, Goose, Aider). IDE = editors/IDEs users open (code-server, JetBrains, VS Code). Utility = everything else (auth, regions, git helpers, file browsers, etc).
- Score each criterion 0, half, or full. Full = implemented AND documented. Half = partial, awkward, or under-documented. Zero = absent.
- Apply "if applicable" exclusions per the rubric: when a concern does not exist by construction, mark the criterion N/A, exclude its points from the denominator, and normalize the final score to 100.
- Utility modules skip the track section (denominator 75 before any N/A exclusions), then normalize: round(raw / denominator * 100).
- Notes must be specific and evidence-based (reference actual variables, README sections, or files you saw). Never invent features.

Output ONLY the scorecard markdown in EXACTLY this structure (this example shows an Agent module; use IDE Integration or omit the track section for Utility):

| Presentation & Onboarding | Agent Integration | Credential Hygiene | Restricted-Network Readiness | Engineering Quality | Overall |
|---:|---:|---:|---:|---:|---:|
| **X / 25** | **X / 25** | **X / 20** | **X / 20 or N/A** | **X / 10** | **X / 100** |

<details>
<summary><strong>Drilldown</strong></summary>

#### Presentation & Onboarding — X / 25

| Criterion | Max | Score | Notes |
|---|---:|---:|---|
| Configuration-mode examples | 12 | X | ... |
| Coder-context framing | 8 | X | ... |
| Visual preview | 5 | X | ... |

(...remaining theme tables in rubric order, highest weight first, each with per-criterion rows...)

#### Overall — X / 100

(If normalized, show: Raw X / Y → round(X / Y × 100) = **Z**)

</details>

Do not add any prose before or after the scorecard.`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": process.env.ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) {
    throw new Error(`Anthropic API error ${res.status}: ${await res.text()}`);
  }
  const data = (await res.json()) as {
    content: { type: string; text?: string }[];
  };
  const text = data.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n");
  return fixOverall(text.trim());
}

async function graphql<T>(
  query: string,
  variables: Record<string, unknown>,
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

async function findDiscussion(
  title: string,
): Promise<{ id: string; url: string } | null> {
  const q = `"${title}" in:title repo:${REPO_OWNER}/${REPO_NAME}`;
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
    { q },
  );
  return data.search.nodes.find((n) => n.title === title) ?? null;
}

async function upsertDiscussion(
  title: string,
  body: string,
): Promise<{ id: string; url: string; created: boolean }> {
  const existing = await findDiscussion(title);
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
    return { id: existing.id, url: existing.url, created: false };
  }
  const data = await graphql<{
    createDiscussion: { discussion: { id: string; url: string } };
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
            id
            url
          }
        }
      }
    `,
    { repoId: REPO_ID, catId: CATEGORY_ID, title, body },
  );
  return { ...data.createDiscussion.discussion, created: true };
}

function discussionBody(
  moduleName: string,
  name: string,
  scorecard: string,
): string {
  const now = new Date().toISOString().slice(0, 10);
  return `A discussion dedicated to the [${name}](https://registry.coder.com/modules/coder/${moduleName}) module. Share your thoughts, questions, and feedback here.

## Module Scorecard

${scorecard}

---
Scored against [SCORECARD.md](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/.github/scorecard/SCORECARD.md) on ${now} with \`${ANTHROPIC_MODEL}\`.
${MARKER}`;
}

async function main() {
  const args = parseArgs();
  if (!process.env.ANTHROPIC_API_KEY)
    throw new Error("ANTHROPIC_API_KEY not set");
  if (!args.dryRun && !process.env.GITHUB_DISCUSSIONS_TOKEN) {
    throw new Error("GITHUB_DISCUSSIONS_TOKEN not set");
  }

  const rubric = await readFile(SCORECARD_PATH, "utf8");
  let modules =
    args.modules ??
    (await readdir(MODULES_DIR, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
  if (args.limit) modules = modules.slice(0, args.limit);

  for (const mod of modules) {
    if (!existsSync(path.join(MODULES_DIR, mod, "README.md"))) {
      console.error(`skip ${mod}: no README.md`);
      continue;
    }
    process.stderr.write(`scoring ${mod}... `);
    try {
      const scorecard = await scoreModule(mod, rubric);
      if (args.dryRun) {
        console.log(`\n===== coder/${mod} =====\n${scorecard}\n`);
        process.stderr.write("done (dry-run)\n");
        continue;
      }
      const name = await displayName(mod);
      const { url, created } = await upsertDiscussion(
        `${name} module`,
        discussionBody(mod, name, scorecard),
      );
      const summary = parseSummary(scorecard);
      if (summary) {
        await saveResult({
          module: mod,
          name,
          url,
          scoredAt: new Date().toISOString(),
          ...summary,
        });
      } else {
        process.stderr.write(`warn: could not parse summary for ${mod}\n`);
      }
      process.stderr.write(`${created ? "created" : "updated"} ${url}\n`);
    } catch (err) {
      process.stderr.write(`FAILED: ${err}\n`);
    }
  }
}

main();
