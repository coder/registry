/**
 * Shared constants, types, and helpers for the module scorecard scripts.
 */

export const REPO_OWNER = "coder";
export const REPO_NAME = "registry";
export const REPO_ID = "R_kgDOOVbRAA"; // coder/registry
export const CATEGORY_ID = "DIC_kwDOOVbRAM4DBMLT"; // "Modules" category

export const MARKER = "<!-- module-scorecard -->";
export const INDEX_MARKER = "<!-- module-scorecard-index -->";
export const INDEX_TITLE = "📊 Module Scorecards";

export interface SummaryScores {
  track: "Agent" | "IDE" | "Utility";
  presentation: string;
  integration: string;
  credential: string;
  network: string;
  engineering: string;
  overall: string;
  overallNum: number;
}

export interface Result extends SummaryScores {
  module: string;
  name: string;
  url: string;
  scoredAt: string;
}

export async function graphql<T>(
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

// Parses the theme-level summary table out of scorecard markdown (either a
// raw scorecard or a discussion body containing one).
export function parseSummary(markdown: string): SummaryScores | null {
  const lines = markdown.split("\n");
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
    integration: integrationIdx === -1 ? "—" : cells[integrationIdx],
    credential: get("credential"),
    network: get("restricted"),
    engineering: get("engineering"),
    overall,
    overallNum: Number(overall.match(/(\d+)\s*\/\s*100/)?.[1] ?? 0),
  };
}

export interface DiscussionRef {
  id: string;
  title: string;
  url: string;
  body: string;
}

export async function findDiscussionByTitle(
  title: string,
): Promise<DiscussionRef | null> {
  const q = `"${title}" in:title repo:${REPO_OWNER}/${REPO_NAME}`;
  const data = await graphql<{ search: { nodes: DiscussionRef[] } }>(
    `
      query ($q: String!) {
        search(query: $q, type: DISCUSSION, first: 10) {
          nodes {
            ... on Discussion {
              id
              title
              url
              body
            }
          }
        }
      }
    `,
    { q },
  );
  return data.search.nodes.find((n) => n.title === title) ?? null;
}

// Finds a module's scorecard discussion by the registry URL in its body,
// regardless of title. Used to detect display_name renames, where the
// title lookup misses but the discussion still exists.
export async function findDiscussionByModuleUrl(
  module: string,
): Promise<DiscussionRef | null> {
  const url = `registry.coder.com/modules/coder/${module}`;
  const q = `"${url}" in:body repo:${REPO_OWNER}/${REPO_NAME}`;
  const data = await graphql<{ search: { nodes: DiscussionRef[] } }>(
    `
      query ($q: String!) {
        search(query: $q, type: DISCUSSION, first: 10) {
          nodes {
            ... on Discussion {
              id
              title
              url
              body
            }
          }
        }
      }
    `,
    { q },
  );
  return (
    data.search.nodes.find(
      (n) => n.body.includes(MARKER) && n.body.includes(`/${module})`),
    ) ?? null
  );
}
