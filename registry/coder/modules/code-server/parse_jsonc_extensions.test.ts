import { describe, expect, it } from "bun:test";
import { spawn, readableStreamToText } from "bun";
import { unlink } from "node:fs/promises";
import { join } from "node:path";

const PARSER = join(import.meta.dir, "parse_jsonc_extensions.js");
const TMP = join(import.meta.dir, "tmp_test.json");

async function parseExtensions(
  json: string,
  query?: string,
): Promise<string[]> {
  await Bun.write(TMP, json);
  try {
    const proc = spawn([process.execPath, PARSER], {
      env: { FILE: TMP, QUERY: query ?? "recommendations" },
      stdout: "pipe",
      stderr: "pipe",
    });
    const out = await readableStreamToText(proc.stdout);
    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      throw new Error(await readableStreamToText(proc.stderr));
    }
    return out.trim().split("\n").filter(Boolean);
  } finally {
    await unlink(TMP).catch(() => {});
  }
}

describe("parse_jsonc_extensions", () => {
  it("handles comments and trailing commas", async () => {
    const result = await parseExtensions(`{
      // line comment
      "recommendations": [
        "ms-python.python",
        /* block comment */
        "dbaeumer.vscode-eslint",  // inline
      ],
    }`);
    expect(result).toEqual(["ms-python.python", "dbaeumer.vscode-eslint"]);
  });

  it("does not mangle URLs in strings", async () => {
    const result = await parseExtensions(`{
      "recommendations": [
        "ms-python.python",
        "https://example.com/custom.vsix"
      ]
    }`);
    expect(result).toEqual([
      "ms-python.python",
      "https://example.com/custom.vsix",
    ]);
  });

  // Hardening: extension IDs can only contain [a-z0-9-] per vsce's nameRegex,
  // so ",]" / ",}" cannot appear in practice. This test guards against the
  // trailing-comma removal corrupting arbitrary string values just in case.
  it("does not strip commas inside string values", async () => {
    const result = await parseExtensions(`{
      "recommendations": [
        "value-with,]-inside",
        "value-with,}-inside",
      ]
    }`);
    expect(result).toEqual(["value-with,]-inside", "value-with,}-inside"]);
  });

  it("handles .code-workspace format", async () => {
    const result = await parseExtensions(
      `{
      "folders": [{"path": "."}],
      "extensions": {
        // Recommended
        "recommendations": ["ms-python.python"],
      },
    }`,
      "extensions.recommendations",
    );
    expect(result).toEqual(["ms-python.python"]);
  });
});
