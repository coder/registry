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
 * Module specs are either a bare name (a module in registry/coder/modules)
 * or namespace/name for any registry namespace. Non-coder namespaces are
 * PR-report or dry-run only; discussions exist solely for coder modules.
 *
 * --dry-run prints scorecards to stdout and skips GitHub entirely.
 */

import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  CATEGORY_ID,
  MARKER,
  REPO_ID,
  REPO_NAME,
  REPO_OWNER,
  type SummaryScores,
  findDiscussionByModuleUrl,
  findDiscussionByTitle,
  graphql,
  parseSummary,
} from "./lib";

const REGISTRY_ROOT = path.resolve(import.meta.dir, "..", "..");
const MODULES_DIR = path.join(REGISTRY_ROOT, "registry", "coder", "modules");
const SCORECARD_PATH = path.join(import.meta.dir, "SCORECARD.md");

const ANTHROPIC_MODEL = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5";
const MAX_FILE_BYTES = 30_000;

// A module reference: bare names mean the coder namespace, and
// namespace/name addresses any registry namespace.
interface ModuleSpec {
  ns: string;
  name: string;
  // namespace/name, used in report headings and log lines.
  label: string;
  dir: string;
}

function toSpec(raw: string): ModuleSpec {
  const slash = raw.indexOf("/");
  const [ns, name] =
    slash === -1 ? ["coder", raw] : [raw.slice(0, slash), raw.slice(slash + 1)];
  return {
    ns,
    name,
    label: `${ns}/${name}`,
    dir: path.join(REGISTRY_ROOT, "registry", ns, "modules", name),
  };
}

async function displayName(spec: ModuleSpec): Promise<string> {
  const readme = await readFile(path.join(spec.dir, "README.md"), "utf8");
  const match = readme.match(/^display_name:\s*["']?([^"'\n]+)["']?\s*$/m);
  return match ? match[1].trim() : spec.name;
}

// Internal building-block modules caution against direct use and are not
// meant to be consumed by template authors, so they are excluded from
// scoring entirely.
async function isInternalBuildingBlock(spec: ModuleSpec): Promise<boolean> {
  const readme = await readFile(path.join(spec.dir, "README.md"), "utf8");
  return /do not recommend using this module directly|not intended to be used directly|internal building block/i.test(
    readme,
  );
}

interface Args {
  modules?: string[];
  dryRun: boolean;
  limit?: number;
  prReport?: string;
}

interface ImageVerification {
  reference: string;
  resolvedPath: string;
  exists: boolean;
  sizeBytes?: number;
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
      case "--pr-report":
        args.prReport = argv[++i];
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

async function verifyReadmeImages(
  spec: ModuleSpec,
): Promise<ImageVerification[]> {
  const readmePath = path.join(spec.dir, "README.md");
  const readme = await readFile(readmePath, "utf8");
  const moduleDir = spec.dir;
  const imageRegex = /!\[[^\]]*\]\(([^)]+)\)/g;
  const results: ImageVerification[] = [];

  let match: RegExpExecArray | null;
  while ((match = imageRegex.exec(readme)) !== null) {
    const reference = match[1];

    if (reference.startsWith("http://") || reference.startsWith("https://")) {
      results.push({
        reference,
        resolvedPath: "(external)",
        exists: true,
      });
      continue;
    }

    if (path.isAbsolute(reference)) {
      continue;
    }

    const resolvedPath = path.resolve(moduleDir, reference);
    if (!resolvedPath.startsWith(REGISTRY_ROOT)) {
      continue;
    }

    const verification: ImageVerification = {
      reference,
      resolvedPath,
      exists: existsSync(resolvedPath),
    };

    if (verification.exists) {
      try {
        const { stat } = await import("node:fs/promises");
        const stats = await stat(resolvedPath);
        verification.sizeBytes = stats.size;
      } catch {}
    }

    results.push(verification);
  }

  return results;
}

async function gatherModuleContext(spec: ModuleSpec): Promise<string> {
  const dir = spec.dir;
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

  const imageVerifications = await verifyReadmeImages(spec);
  if (imageVerifications.length > 0) {
    const verificationLines = imageVerifications.map((v) => {
      if (v.resolvedPath === "(external)") {
        return `  → ${v.reference} — external URL`;
      } else if (v.exists) {
        const size = v.sizeBytes
          ? ` (${(v.sizeBytes / 1024).toFixed(1)} KB)`
          : "";
        return `  ✓ ${v.reference} — exists${size}`;
      } else {
        return `  ✗ ${v.reference} — NOT FOUND`;
      }
    });
    parts.push(
      `=== README IMAGE VERIFICATION ===\n${verificationLines.join("\n")}`,
    );
  }

  return parts.join("\n\n");
}

function fixOverall(scorecard: string): string {
  // Find the summary table's data row: first row whose cells are bold
  // "**a / b**" fractions (or N/A), ending with the overall cell. The
  // overall cell may use any denominator (e.g. "67 / 75" from a utility
  // module); it is recomputed and rewritten as "/ 100" regardless.
  const lines = scorecard.split("\n");
  const rowIdx = lines.findIndex((l) => {
    const t = l.trim();
    if (!/^\|\s*(\*\*\d|N\/A)/i.test(t)) return false;
    const cells = t.split("|").filter((c) => c.trim() !== "");
    return (
      cells.length >= 3 &&
      cells.every((c) => /n\/a/i.test(c) || /\d+\s*\/\s*\d+/.test(c))
    );
  });
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
    /#### Overall — \d+(?:\.\d+)? \/ \d+/g,
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

async function scoreModule(spec: ModuleSpec, rubric: string): Promise<string> {
  const context = await gatherModuleContext(spec);
  const prompt = `You are scoring a Coder Registry module against a scorecard rubric.

<rubric>
${rubric}
</rubric>

<module name="${spec.label}">
${context}
</module>

Score the module strictly against the rubric. Rules:
- First decide the track: Agent, IDE, or Utility. Agent = AI coding agents (CLI agents like Claude Code, Goose, Aider). IDE = editors/IDEs users open (code-server, JetBrains, VS Code). Utility = everything else (auth, regions, git helpers, file browsers, etc).
- Score each criterion 0, half, or full. Full = implemented AND documented. Half = partial, awkward, or under-documented. Zero = absent.
- BE STRICT. When evidence is ambiguous or missing, score lower. Never rationalize credit.
- Never credit workarounds achievable outside the module. "The URL could be proxied or mirrored at the network level" is NOT a mirrorable artifact source; that criterion requires an actual module input variable that overrides the download/install URL. A hardcoded URL scores 0 regardless of what admins could do around it.
- "Documented" means an explicit README section or example. Endpoints or behavior that are merely implicit, inferable, or visible only in source code do not count as documented.
- Apply "if applicable" exclusions per the rubric: when a concern does not exist by construction, mark the criterion N/A, exclude its points from the denominator, and normalize the final score to 100. Do not use N/A for concerns that exist but are unaddressed.
- Utility modules skip the track section (denominator 75 before any N/A exclusions), then normalize: round(raw / denominator * 100).
- Notes must be specific and evidence-based (reference actual variables, README sections, or files you saw). Never invent features.

Calibration anchors. Apply these literally; they override any generous reading:
- Visual preview: 0 unless the README embeds an actual image, GIF, or video. Icons and links do not count.
- Secrets marked sensitive: README examples that inline literal or placeholder keys (like api_key = "xxxx-xxxxx-xxxx") count as inline secrets, capping this criterion at half even when module inputs are marked sensitive.
- AI governance covers AI Gateway AND Agent Firewall. Full credit requires both documented; exactly one documented earns half. Support that a README says was dropped or removed counts as absent.
- Session continuity: 0 unless the README explicitly documents resuming sessions or running in a persistent session manager.
- Egress transparency: without a dedicated network/offline/air-gapped README section, at most half, no matter how many endpoints appear across examples.
- Mirrorable artifact source and Bring-your-own binary are distinct. Offline or skip-install modes belong to Bring-your-own binary ONLY and never earn Mirrorable credit. To give ANY Mirrorable credit you must name, in the notes, the exact module variable whose value replaces the tool's download URL in the install path. Install-location variables (like install_prefix), version pins, and cache/offline toggles are not download URL overrides. If you cannot name such a variable, score 0. Never use "could be mirrored", "effectively", or "spirit of the criterion" reasoning.
- Egress transparency full credit requires the dedicated section to enumerate the actual endpoints or domains contacted. A section that describes offline behavior without listing endpoints earns half.
- Runs without sudo: inspect the actual scripts. Full only if they never invoke sudo or degrade gracefully when it is absent. Root required for core functionality scores 0. Sudo used only for optional features with a working non-root fallback earns half.
- Restricted-Environment N/A: the download-related criteria (Mirrorable artifact source, Bring-your-own binary, Egress transparency) go N/A when the module downloads or installs nothing of its own (for example, it only invokes tools already in the image or calls the Coder API). A module whose only external interaction is operating on user-provided URLs (like cloning a repo the caller specifies) downloads nothing of its own. Runs without sudo applies whenever the module executes any script, and goes N/A only for modules with no scripts at all. Score 0 only when a concern exists and the module lacks the capability.
- Runs without sudo is an exception to the documentation requirement: scripts that verifiably never invoke sudo earn full credit from the code alone, no README mention needed.
- Half credit is exactly half the criterion's max points, not an arbitrary fraction.
- A perfect theme score should be rare. If you scored every criterion in a theme full, re-check each against its disqualifiers before finalizing.

Output ONLY the scorecard markdown in EXACTLY this structure (this example shows an Agent module; use IDE Integration or omit the track section for Utility):

| Presentation & Onboarding | Agent Integration | Credential Hygiene | Restricted-Environment Readiness | Engineering Quality | Overall |
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
      temperature: 0,
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

async function upsertDiscussion(
  title: string,
  body: string,
): Promise<{ id: string; url: string; created: boolean }> {
  const existing = await findDiscussionByTitle(title);
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

// Builds one PR-report section comparing a fresh scorecard against the
// module's current discussion (the last scoring from main), so PRs can see
// whether they improve, regress, or hold the score.
function prReportSection(
  spec: ModuleSpec,
  name: string,
  scorecard: string,
  summary: SummaryScores | null,
  baseline: (SummaryScores & { url: string }) | null,
): string {
  const details = `<details>\n<summary><strong>Full scorecard for this PR</strong></summary>\n\n${scorecard}\n\n</details>`;
  if (!summary) {
    return `### \`${spec.label}\`\n\nCould not parse the generated scorecard; see full output below.\n\n${details}`;
  }
  if (!baseline) {
    // Discussions exist only for coder-namespace modules; community
    // modules always get a standalone advisory score.
    const followup =
      spec.ns === "coder"
        ? `No existing scorecard discussion found for ${name}; this is the initial score. A dedicated discussion is created after merge.`
        : "No specific score is required to contribute, but modules with higher scores are more likely to be approved by the Coder team and widely used.";
    return `### \`${spec.label}\`: first scorecard, **${summary.overall}**\n\n${followup}\n\n${details}`;
  }
  const delta = summary.overallNum - baseline.overallNum;
  const themes: [string, string, string][] = [
    ["Presentation & Onboarding", baseline.presentation, summary.presentation],
    ["Integration", baseline.integration, summary.integration],
    ["Credential Hygiene", baseline.credential, summary.credential],
    ["Restricted-Environment", baseline.network, summary.network],
    ["Engineering Quality", baseline.engineering, summary.engineering],
    ["**Overall**", `**${baseline.overall}**`, `**${summary.overall}**`],
  ];
  const table = [
    "| Theme | Before | After |",
    "|---|---:|---:|",
    ...themes.map(([t, b, a]) => `| ${t} | ${b} | ${a} |`),
  ].join("\n");
  let verdict: string;
  if (delta < 0) {
    verdict = `\u26a0\ufe0f **Score regression**: ${baseline.overallNum} \u2192 ${summary.overallNum} (${delta}). Check the drilldown for which criteria dropped.`;
  } else if (delta > 0) {
    verdict = `\u2705 **Score improvement**: ${baseline.overallNum} \u2192 ${summary.overallNum} (+${delta}).`;
  } else {
    verdict = `\u2705 **Score unchanged** at ${summary.overall}. This PR does not affect the module's scorecard; the results are still good.`;
  }
  return `### [\`${spec.label}\`](${baseline.url}): ${baseline.overallNum} \u2192 ${summary.overallNum}\n\n${verdict}\n\n${table}\n\n${details}`;
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
  // Without --modules, enumerate only registry/coder/modules: the
  // discussion-writing runs (post-merge, weekly) are for official modules
  // only. Community modules are scored solely via explicit --modules specs
  // in PR-report mode.
  let specs = (
    args.modules ??
    (await readdir(MODULES_DIR, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort()
  ).map(toSpec);
  if (args.limit) specs = specs.slice(0, args.limit);

  // Discussions are reserved for coder-namespace modules. Refuse to run
  // non-coder specs in discussion-writing mode rather than silently
  // creating community discussions.
  if (!args.prReport && !args.dryRun) {
    const community = specs.filter((s) => s.ns !== "coder");
    if (community.length > 0) {
      throw new Error(
        `non-coder modules require --pr-report or --dry-run: ${community.map((s) => s.label).join(", ")}`,
      );
    }
  }

  const prSections: string[] = [];
  const failed: string[] = [];
  for (const spec of specs) {
    if (!existsSync(path.join(spec.dir, "README.md"))) {
      console.error(`skip ${spec.label}: no README.md`);
      continue;
    }
    if (await isInternalBuildingBlock(spec)) {
      process.stderr.write(`skip ${spec.label}: internal building block\n`);
      continue;
    }
    process.stderr.write(`scoring ${spec.label}... `);
    try {
      const scorecard = await scoreModule(spec, rubric);
      if (args.dryRun) {
        console.log(`\n===== ${spec.label} =====\n${scorecard}\n`);
        process.stderr.write("done (dry-run)\n");
        continue;
      }
      const name = await displayName(spec);
      if (args.prReport) {
        // PR mode: compare against the module's current discussion and
        // build a report instead of touching any discussion. Community
        // modules have no discussions, so they skip the baseline lookup
        // and always report a standalone score.
        const summary = parseSummary(scorecard);
        let existing =
          spec.ns === "coder"
            ? await findDiscussionByTitle(`${name} module`)
            : null;
        let renameWarning = "";
        if (spec.ns === "coder" && !existing) {
          // A display_name rename breaks the title lookup while the old
          // discussion still exists. Fall back to the registry URL and
          // flag it so a reviewer retitles or deletes the old one; the
          // post-merge run creates a fresh discussion under the new name.
          existing = await findDiscussionByModuleUrl(spec.name);
          if (existing) {
            renameWarning = `\n\n> [!WARNING]\n> This module's display name appears to have changed. Its existing scorecard discussion is titled "${existing.title}" (${existing.url}). After merge, a new discussion named "${name} module" will be created; a maintainer should retitle or delete the old one to avoid duplicates.`;
          }
        }
        const parsed = existing ? parseSummary(existing.body) : null;
        const baseline =
          existing && parsed ? { ...parsed, url: existing.url } : null;
        prSections.push(
          prReportSection(spec, name, scorecard, summary, baseline) +
            renameWarning,
        );
        process.stderr.write("compared\n");
        continue;
      }
      const { url, created } = await upsertDiscussion(
        `${name} module`,
        discussionBody(spec.name, name, scorecard),
      );
      process.stderr.write(`${created ? "created" : "updated"} ${url}\n`);
    } catch (err) {
      failed.push(spec.label);
      process.stderr.write(`FAILED: ${err}\n`);
    }
  }

  if (failed.length > 0) {
    process.stderr.write(
      `\n${failed.length} module(s) failed to score: ${failed.join(", ")}\n`,
    );
    process.exitCode = 1;
  }

  if (args.prReport) {
    const report =
      prSections.length > 0
        ? `## Module Scorecard Check\n\n${prSections.join("\n\n")}\n\n---\nScored against [SCORECARD.md](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/.github/scorecard/SCORECARD.md) with \`${ANTHROPIC_MODEL}\`. Language-model scores are advisory.\n<!-- module-scorecard-pr -->`
        : "";
    await Bun.write(args.prReport, report);
    process.stderr.write(`wrote PR report to ${args.prReport}\n`);
  }
}

main();
