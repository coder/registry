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

// Returns shell commands that write a bash script with `body` to `path`.
// Both are base64-encoded so that any character reaches the container intact.
const writeScriptCommand = (
  path: string,
  body: string,
  { executable = true } = {},
) => {
  const encodedPath = Buffer.from(path).toString("base64");
  const content = Buffer.from(`#!/usr/bin/env bash\n${body}\n`).toString(
    "base64",
  );

  const commands = [
    `file="$(printf '%s' '${encodedPath}' | base64 -d)"`,
    'mkdir -p "$(dirname "$file")"',
    `printf '%s' '${content}' | base64 -d > "$file"`,
  ];
  if (executable) {
    commands.push('chmod +x "$file"');
  }
  return commands.join("\n");
};

const utf8Locale = ["LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8"];

// Renders the module, runs `setup`, the start or stop script and `inspect` as
// root in a fresh container, and returns the script's output and the output of
// `inspect`.
const runPersonalize = async ({
  phase = "start",
  path = "~/personalize",
  setup = "",
  inspect = "",
  environment = utf8Locale,
} = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    path,
  });
  const resourceName = phase === "start" ? "personalize" : "personalize_stop";
  const script = findResourceInstance(
    state,
    "coder_script",
    resourceName,
  ).script;

  const id = await runContainer("codercom/example-base:ubuntu");
  const runBash = (command: string) =>
    execContainer(
      id,
      ["env", ...environment, "bash", "-c", command],
      ["--user", "root"],
    );
  try {
    const preparation = await runBash(setup);
    expect(preparation.exitCode, preparation.stderr).toBe(0);

    const output = await runBash(script);

    const inspection = await runBash(inspect);
    expect(inspection.exitCode, inspection.stderr).toBe(0);

    return {
      ...output,
      stdout: output.stdout.trim(),
      inspection: inspection.stdout.trim(),
    };
  } finally {
    await removeContainer(id);
  }
};

setDefaultTimeout(30 * 1000);

describe("personalize", async () => {
  await runTerraformInit(import.meta.dir);
  testRequiredVariables(import.meta.dir, { agent_id: "foo" });

  it("prints the v1 hint and discovery paths when neither path exists", async () => {
    const output = await runPersonalize();

    expect(output.exitCode).toBe(0);
    expect(output.stdout.split("\n")).toEqual([
      "✨ \u001b[0;1mYou don't have a personalize script!",
      "",
      "Create a script at \u001b[36;40;1m~/personalize\u001b[0m and make it executable.",
      "It will run every time your workspace starts. Use it to install personal packages!",
      "",
      "Add executable drop-in scripts to \u001b[36;40;1m~/personalize.d\u001b[0m; find the module configuration at /root/.coder-modules/coder/personalize/config.",
    ]);
  });

  it("keeps the v1 notice for a non-executable personalize script", async () => {
    const setup = writeScriptCommand(
      "/root/personalize",
      "echo should-not-run",
      {
        executable: false,
      },
    );

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe(
      "🔐 Your personalize script isn't executable!\nMake \u001b[36;40;1m~/personalize\u001b[0m executable before restarting the workspace.",
    );
  });

  it("runs the personalize script without arguments", async () => {
    const setup = writeScriptCommand(
      "/root/personalize",
      'printf "arguments=%s\\n" "$#"',
    );

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe("arguments=0");
  });

  it("runs a literal custom path and round-trips its config through sh and bash", async () => {
    const path = "/tmp/personalize scripts/'$(printf injected) [daily]*";
    const setup = writeScriptCommand(path, "echo custom");
    const printConfig =
      '. "$HOME/.coder-modules/coder/personalize/config"; printf "%s\\n" "$PERSONALIZE_PATH" "$PERSONALIZE_DIR" "$PERSONALIZE_LOG_DIR"';
    const inspect = `sh -c '${printConfig}' && bash -c '${printConfig}'`;

    const output = await runPersonalize({ path, setup, inspect });

    const expectedConfig = [
      path,
      `${path}.d`,
      "/root/.coder-modules/coder/personalize/logs",
    ];
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe("custom");
    expect(output.inspection.split("\n")).toEqual([
      ...expectedConfig,
      ...expectedConfig,
    ]);
  });

  it("keeps the personalize script's failure and still runs drop-ins", async () => {
    const setup = [
      writeScriptCommand("/root/personalize", "exit 23"),
      writeScriptCommand("/root/personalize.d/10-fail", "exit 17"),
      writeScriptCommand("/root/personalize.d/20-later", "echo later"),
    ].join("\n");

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(23);
    expect(output.stdout).toBe("later");
    expect(output.stderr).toContain("23");
    expect(output.stderr).toContain("17");
  });

  it("runs start in byte order and stop in reverse order under a UTF-8 locale", async () => {
    const printNameAndArguments =
      'printf "%s %s argc=%s\\n" "${0##*/}" "$1" "$#"';
    const setup = [
      writeScriptCommand("/root/personalize", 'echo "personalize $#"'),
      writeScriptCommand("/root/personalize.d/a-lower", printNameAndArguments),
      writeScriptCommand("/root/personalize.d/20-last", printNameAndArguments),
      writeScriptCommand("/root/personalize.d/A-upper", printNameAndArguments),
      writeScriptCommand(
        "/root/personalize.d/10 first.sh",
        printNameAndArguments,
      ),
    ].join("\n");
    const expectedStdout = {
      start: [
        "personalize 0",
        "10 first.sh start argc=1",
        "20-last start argc=1",
        "A-upper start argc=1",
        "a-lower start argc=1",
      ],
      stop: [
        "a-lower stop argc=1",
        "A-upper stop argc=1",
        "20-last stop argc=1",
        "10 first.sh stop argc=1",
      ],
    };

    for (const phase of ["start", "stop"] as const) {
      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(0);
      expect(output.stdout.split("\n")).toEqual(expectedStdout[phase]);
    }
  });

  it("continues after drop-in failures and returns the first failing exit code", async () => {
    const setup = [
      writeScriptCommand("/root/personalize", ":"),
      writeScriptCommand("/root/personalize.d/10-fail", "exit 17"),
      writeScriptCommand("/root/personalize.d/20-later", "echo later"),
      writeScriptCommand("/root/personalize.d/30-fail", "exit 19"),
    ].join("\n");
    // Stop runs in reverse order, so 30-fail fails first there.
    const expectedExitCode = { start: 17, stop: 19 };

    for (const phase of ["start", "stop"] as const) {
      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(expectedExitCode[phase]);
      expect(output.stdout).toBe("later");
      expect(output.stderr).toContain("10-fail");
      expect(output.stderr).toContain("30-fail");
    }
  });

  it("skips ineligible files and notices only non-executable regular files", async () => {
    const setup = [
      writeScriptCommand("/root/personalize", ":"),
      writeScriptCommand("/root/personalize.d/disabled", "echo bad", {
        executable: false,
      }),
      writeScriptCommand("/root/personalize.d/.hidden", "echo bad"),
      writeScriptCommand("/root/personalize.d/backup~", "echo bad"),
      "mkdir -p /root/personalize.d/directory",
      "ln -s /missing /root/personalize.d/broken",
    ].join("\n");

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe(
      "Skipping non-executable drop-in script: /root/personalize.d/disabled",
    );
  });

  it("succeeds without a drop-in directory in either phase", async () => {
    const setup = writeScriptCommand("/root/personalize", ":");

    for (const phase of ["start", "stop"]) {
      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(0);
      expect(output.stdout).toBe("");
      expect(output.stderr).toBe("");
    }
  });

  it("runs drop-ins without a personalize script and prints no hint", async () => {
    const setup = writeScriptCommand(
      "/root/personalize.d/10-first",
      'echo "drop-in $1"',
    );

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe("drop-in start");
  });

  it("warns about a failed config write and still runs user scripts", async () => {
    const setup = [
      writeScriptCommand("/root/personalize", "echo personalize"),
      writeScriptCommand("/root/personalize.d/10-first", "echo drop-in"),
      // A file where the module directory should be makes mkdir fail.
      "touch /root/.coder-modules",
    ].join("\n");

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toBe("personalize\ndrop-in");
    expect(output.stderr).toContain(
      "Warning: failed to write personalize config file",
    );
  });

  it("preserves set, empty and unset caller locales for user scripts", async () => {
    const printLocale = 'printf "LC_ALL=%s:%s\\n" "${LC_ALL+x}" "${LC_ALL-}"';
    const setup = [
      writeScriptCommand("/root/personalize", printLocale),
      writeScriptCommand("/root/personalize.d/10-locale", printLocale),
    ].join("\n");
    const cases = [
      { environment: utf8Locale, expected: "LC_ALL=x:en_US.UTF-8" },
      { environment: ["LANG=en_US.UTF-8", "LC_ALL="], expected: "LC_ALL=x:" },
      {
        environment: ["-u", "LC_ALL", "LANG=en_US.UTF-8"],
        expected: "LC_ALL=:",
      },
    ];

    for (const { environment, expected } of cases) {
      const output = await runPersonalize({ setup, environment });

      expect(output.exitCode).toBe(0);
      expect(output.stdout).toBe(`${expected}\n${expected}`);
    }
  });
});
