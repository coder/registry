import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const createScript = (
  path: string,
  content: string,
  executable = true,
): string => {
  const encodedPath = Buffer.from(path).toString("base64");
  const encodedContent = Buffer.from(content).toString("base64");

  return [
    `script_path="$(printf '%s' '${encodedPath}' | base64 -d)"`,
    'mkdir -p "$(dirname "$script_path")"',
    `printf '%s' '${encodedContent}' | base64 -d > "$script_path"`,
    executable ? 'chmod +x "$script_path"' : "",
  ]
    .filter(Boolean)
    .join("\n");
};

const executePersonalize = async ({
  phase = "start",
  path = "~/personalize",
  before = "",
  after = "",
  image = "alpine",
  shell = "sh",
} = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    path,
  });
  const script = findResourceInstance(
    state,
    "coder_script",
    phase === "start" ? "personalize" : "personalize_stop",
  ).script;
  const id = await runContainer(image);
  try {
    if (before) {
      const setup = await execContainer(id, [shell, "-c", before]);
      expect(setup.exitCode, setup.stderr).toBe(0);
    }
    const output = await execContainer(id, [shell, "-c", script]);
    const inspection = after
      ? await execContainer(id, [shell, "-c", after])
      : undefined;
    if (inspection) {
      expect(inspection.exitCode, inspection.stderr).toBe(0);
    }
    return {
      exitCode: output.exitCode,
      stdout: output.stdout.trim().split("\n"),
      stderr: output.stderr.trim().split("\n"),
      inspection: inspection?.stdout.trim().split("\n"),
    };
  } finally {
    await removeContainer(id);
  }
};

setDefaultTimeout(30 * 1000);

describe("personalize", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("warns without personalize script", async () => {
    const output = await executePersonalize();
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "✨ \u001b[0;1mYou don't have a personalize script!",
    );
    expect(output.stdout.join("\n")).toContain("~/personalize.d");
    expect(output.stdout.join("\n")).toContain(
      "/root/.coder-modules/coder/personalize/config",
    );
  });

  it("warns when the personalize script is not executable", async () => {
    const output = await executePersonalize({
      before: createScript(
        "/root/personalize",
        "#!/bin/sh\necho should-not-run\n",
        false,
      ),
    });
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "🔐 Your personalize script isn't executable!",
    );
    expect(output.stdout).not.toContain("should-not-run");
    expect(output.stdout.join("\n")).toContain("~/personalize.d");
  });

  it("runs an executable personalize script without arguments", async () => {
    const output = await executePersonalize({
      before: createScript(
        "/root/personalize",
        "#!/bin/sh\nprintf 'personalize executed: %s\\n' \"$#\"\n",
      ),
    });
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["personalize executed: 0"]);
  });

  it.each(["start", "stop"])(
    "preserves spaces and shell syntax in a custom path at %s",
    async (phase) => {
      const path = "/tmp/personalize scripts/$(printf injected) [daily]*";
      const output = await executePersonalize({
        phase,
        path,
        before: [
          createScript(path, "#!/bin/sh\necho legacy\n"),
          createScript(`${path}.d/10 custom`, '#!/bin/sh\necho "custom $1"\n'),
        ].join("\n"),
      });
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual(
        phase === "start" ? ["legacy", "custom start"] : ["custom stop"],
      );
    },
  );

  it("preserves the personalize script exit code and runs drop-ins after it fails", async () => {
    const output = await executePersonalize({
      before: [
        createScript("/root/personalize", "#!/bin/sh\nexit 23\n"),
        createScript("/root/personalize.d/10-later", "#!/bin/sh\necho later\n"),
      ].join("\n"),
    });
    expect(output.exitCode).toBe(23);
    expect(output.stderr.join("\n")).toContain("23");
    expect(output.stdout).toContain("later");
  });

  it.each(["start", "stop"])(
    "runs eligible drop-ins in %s order with the phase argument",
    async (phase) => {
      const record = (name: string) =>
        `#!/bin/sh\nprintf '${name} %s\\n' "$1" >> /tmp/order\n`;
      const output = await executePersonalize({
        phase,
        before: [
          createScript("/root/personalize", record("legacy")),
          createScript("/root/personalize.d/20-last", record("20")),
          createScript("/root/personalize.d/10 first.sh", record("10")),
          createScript("/root/personalize.d/A-upper", record("A")),
          createScript("/root/personalize.d/a-lower", record("a")),
          createScript("/root/personalize.d/15-disabled", record("bad"), false),
          createScript("/root/personalize.d/.hidden", record("bad")),
          createScript("/root/personalize.d/25-backup~", record("bad")),
          "mkdir -p /root/personalize.d/30-directory",
        ].join("\n"),
        after: "cat /tmp/order",
      });
      expect(output.exitCode).toBe(0);
      expect(output.inspection).toEqual(
        phase === "start"
          ? ["legacy ", "10 start", "20 start", "A start", "a start"]
          : ["a stop", "A stop", "20 stop", "10 stop"],
      );
      expect(output.stdout.join("\n")).toContain("15-disabled");
    },
  );

  it.each(["start", "stop"])(
    "continues after a failing drop-in at %s and returns non-zero",
    async (phase) => {
      const output = await executePersonalize({
        phase,
        before: [
          createScript("/root/personalize", "#!/bin/sh\nexit 0\n"),
          createScript(
            "/root/personalize.d/10-first",
            "#!/bin/sh\necho first\n",
          ),
          createScript("/root/personalize.d/20-fail", "#!/bin/sh\nexit 17\n"),
          createScript("/root/personalize.d/30-last", "#!/bin/sh\necho last\n"),
        ].join("\n"),
      });
      expect(output.exitCode).not.toBe(0);
      expect(output.stdout).toEqual(
        phase === "start" ? ["first", "last"] : ["last", "first"],
      );
      expect(output.stderr.join("\n")).toContain("20-fail");
      expect(output.stderr.join("\n")).toContain("17");
    },
  );

  it.each(["start", "stop"])(
    "succeeds without a drop-in directory at %s",
    async (phase) => {
      const output = await executePersonalize({
        phase,
        before: createScript("/root/personalize", "#!/bin/sh\nexit 0\n"),
      });
      expect(output.exitCode).toBe(0);
      expect(output.stderr).toEqual([""]);
    },
  );

  it.each([
    { image: "alpine", shell: "sh" },
    { image: "debian:bookworm-slim", shell: "dash" },
  ])(
    "writes sourceable configuration using $shell in $image",
    async (runtime) => {
      const path = "/tmp/personalize scripts/'$(printf injected) [daily]*";
      const output = await executePersonalize({
        ...runtime,
        path,
        before: createScript(path, "#!/bin/sh\nexit 0\n"),
        after: [
          '. "$HOME/.coder-modules/coder/personalize/config"',
          'printf "%s\\n" "$PERSONALIZE_PATH" "$PERSONALIZE_DIR" "$PERSONALIZE_LOG_DIR"',
          'test "$(find "$HOME/.coder-modules/coder/personalize" -name "config.*" | wc -l)" -eq 0',
        ].join("\n"),
      });
      expect(output.exitCode).toBe(0);
      expect(output.inspection).toEqual([
        path,
        `${path}.d`,
        "/root/.coder-modules/coder/personalize/logs",
      ]);
    },
  );

  it("resolves a relative path to an absolute config value", async () => {
    const output = await executePersonalize({
      path: "./personalize",
      before: createScript("/personalize", "#!/bin/sh\necho relative\n"),
      after:
        '. "$HOME/.coder-modules/coder/personalize/config"; printf "%s\\n" "$PERSONALIZE_PATH"',
    });
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["relative"]);
    expect(output.inspection).toEqual(["/./personalize"]);
  });
});
