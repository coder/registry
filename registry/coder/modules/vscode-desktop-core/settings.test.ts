import { beforeAll, describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  writeFileContainer,
} from "~test";

setDefaultTimeout(60 * 1000);

const settingsPath = "/root/settings.json";
let settingsScript: string;

beforeAll(async () => {
  await runTerraformInit(import.meta.dir);
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    coder_app_icon: "/icon/code.svg",
    coder_app_slug: "vscode",
    coder_app_display_name: "VS Code Desktop",
    protocol: "vscode",
    config_dir: "$HOME/.vscode",
    settings: JSON.stringify({ "editor.fontSize": 14 }),
    settings_file: settingsPath,
  });
  settingsScript = findResourceInstance(
    state,
    "coder_script",
    "apply_settings",
  ).script;
});

it("runs the Python merge test suite", async () => {
  const id = await runContainer("python:3.12-slim");
  try {
    const mkdir = await execContainer(id, [
      "mkdir",
      "-p",
      "/tmp/scripts",
      "/tmp/tests",
    ]);
    expect(mkdir.exitCode).toBe(0);
    for (const path of [
      "scripts/merge-settings.py",
      "tests/test_merge_settings.py",
    ]) {
      await writeFileContainer(
        id,
        `/tmp/${path}`,
        await Bun.file(`${import.meta.dir}/${path}`).text(),
      );
    }
    const result = await execContainer(id, [
      "python3",
      "-B",
      "-m",
      "unittest",
      "discover",
      "-s",
      "/tmp/tests",
      "-v",
    ]);
    console.log(result.stderr);
    expect(result.exitCode).toBe(0);
  } finally {
    await removeContainer(id);
  }
});

describe("settings file updates", () => {
  it("creates a private file with a trailing newline without Python", async () => {
    const id = await runContainer("node:22-bookworm-slim");
    try {
      const result = await execContainer(id, ["bash", "-c", settingsScript]);
      expect(result.exitCode).toBe(0);
      expect(await readFileContainer(id, settingsPath)).toBe(
        '{"editor.fontSize":14}\n',
      );
      const mode = await execContainer(id, ["stat", "-c", "%a", settingsPath]);
      expect(mode.exitCode).toBe(0);
      expect(mode.stdout.trim()).toBe("600");
    } finally {
      await removeContainer(id);
    }
  });

  it.each([
    ["regular file", "600"],
    ["regular file", "644"],
    ["symlink", "640"],
    ["symlink", "664"],
  ])("preserves permissions of a %s with mode %s", async (kind, mode) => {
    const id = await runContainer("python:3.12-slim");
    const target = kind === "symlink" ? "/root/dotfile.json" : settingsPath;
    try {
      await writeFileContainer(id, target, '{"keep": true}');
      const chmod = await execContainer(id, ["chmod", mode, target]);
      expect(chmod.exitCode).toBe(0);
      if (kind === "symlink") {
        const link = await execContainer(id, [
          "ln",
          "-s",
          target,
          settingsPath,
        ]);
        expect(link.exitCode).toBe(0);
      }
      const result = await execContainer(id, ["bash", "-c", settingsScript]);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);
      expect(JSON.parse(await readFileContainer(id, target))).toEqual({
        keep: true,
        "editor.fontSize": 14,
      });
      const actualMode = await execContainer(id, ["stat", "-c", "%a", target]);
      expect(actualMode.exitCode).toBe(0);
      expect(actualMode.stdout.trim()).toBe(mode);
      if (kind === "symlink") {
        const link = await execContainer(id, ["readlink", settingsPath]);
        expect(link.exitCode).toBe(0);
        expect(link.stdout.trim()).toBe(target);
      }
    } finally {
      await removeContainer(id);
    }
  });

  it.each([
    [
      "invalid JSON",
      '{"broken":}',
      "Cannot parse the existing IDE settings file:",
    ],
    ["unterminated comment", "{} /* unfinished", "unterminated block comment"],
    ["non-object root", "[]", "must contain a JSON object"],
  ])(
    "leaves a symlink and its target untouched on %s",
    async (_name, source, message) => {
      const id = await runContainer("python:3.12-slim");
      const target = "/root/dotfile.json";
      try {
        await writeFileContainer(id, target, source);
        const link = await execContainer(id, [
          "ln",
          "-s",
          target,
          settingsPath,
        ]);
        expect(link.exitCode).toBe(0);
        const result = await execContainer(id, ["bash", "-c", settingsScript]);
        expect(result.exitCode).toBe(1);
        expect(result.stderr).toContain(message);
        expect(result.stderr).not.toContain("Traceback");
        expect(result.stderr.trim().split("\n")).toHaveLength(1);
        expect(await readFileContainer(id, target)).toBe(source);
        const preservedLink = await execContainer(id, [
          "readlink",
          settingsPath,
        ]);
        expect(preservedLink.exitCode).toBe(0);
        expect(preservedLink.stdout.trim()).toBe(target);
        const temps = await execContainer(id, [
          "find",
          "/root",
          "-name",
          ".coder-settings.*",
        ]);
        expect(temps.exitCode).toBe(0);
        expect(temps.stdout).toBe("");
      } finally {
        await removeContainer(id);
      }
    },
  );
});
