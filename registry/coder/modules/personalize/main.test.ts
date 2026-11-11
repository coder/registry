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

// Returns shell commands that write `content` to `path` and, unless
// `executable` is false, make it executable. Both are base64-encoded so that
// any characters survive the trip into the container.
const writeScriptCommand = (
  path: string,
  content: string,
  { executable = true } = {},
): string => {
  const encodedPath = Buffer.from(path).toString("base64");
  const encodedContent = Buffer.from(content).toString("base64");

  const commands = [
    `script_path="$(printf '%s' '${encodedPath}' | base64 -d)"`,
    'mkdir -p "$(dirname "$script_path")"',
    `printf '%s' '${encodedContent}' | base64 -d > "$script_path"`,
  ];
  if (executable) {
    commands.push('chmod +x "$script_path"');
  }
  return commands.join("\n");
};

const printingScript = (text: string) => `#!/bin/sh\necho ${text}\n`;

const exitingScript = (code: number) => `#!/bin/sh\nexit ${code}\n`;

// A script that prints `name` followed by its first argument.
const argumentPrintingScript = (name: string) =>
  `#!/bin/sh\nprintf "${name} %s\\n" "$1"\n`;

const unprivilegedUser = "65534:65534";
const unprivilegedHome = "/tmp/personalize-home";
const createUnprivilegedHome = `mkdir -p ${unprivilegedHome}; chown ${unprivilegedUser} ${unprivilegedHome}`;

const splitLines = (text: string) => text.trim().split("\n");

interface PersonalizeRun {
  // "start" runs coder_script.personalize, anything else
  // coder_script.personalize_stop.
  phase?: string;
  path?: string;
  // Shell commands run as root before the module script.
  setup?: string;
  // Shell commands run after the module script, as the same user and with the
  // same environment. Their stdout is returned as `inspection`.
  inspect?: string;
  image?: string;
  shell?: string;
  // Arguments for env(1) in front of the shell, such as VAR=value or -u VAR.
  environment?: readonly string[];
  user?: string;
}

// Renders the module, runs one of its scripts in a fresh container and
// returns the script's exit code and output lines.
const runPersonalize = async ({
  phase = "start",
  path = "~/personalize",
  setup = "",
  inspect = "",
  image = "alpine",
  shell = "sh",
  environment = [],
  user = "root",
}: PersonalizeRun = {}) => {
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

  const id = await runContainer(image);
  try {
    if (setup) {
      const setupResult = await execContainer(
        id,
        [shell, "-c", setup],
        ["--user", "root"],
      );
      expect(setupResult.exitCode, setupResult.stderr).toBe(0);
    }

    const output = await execContainer(
      id,
      ["env", ...environment, shell, "-c", script],
      ["--user", user],
    );

    let inspection: string[] | undefined;
    if (inspect) {
      const inspectResult = await execContainer(
        id,
        ["env", ...environment, shell, "-c", inspect],
        ["--user", user],
      );
      expect(inspectResult.exitCode, inspectResult.stderr).toBe(0);
      inspection = splitLines(inspectResult.stdout);
    }

    return {
      exitCode: output.exitCode,
      stdout: splitLines(output.stdout),
      stderr: splitLines(output.stderr),
      inspection,
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
    const output = await runPersonalize();

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual([
      "✨ \u001b[0;1mYou don't have a personalize script!",
      "",
      "Create a script at \u001b[36;40;1m~/personalize\u001b[0m and make it executable.",
      "It will run every time your workspace starts. Use it to install personal packages!",
      "",
      "Add executable drop-in scripts to \u001b[36;40;1m~/personalize.d\u001b[0m; they receive start or stop.",
      "Find the module configuration at /root/.coder-modules/coder/personalize/config.",
    ]);
  });

  it("omits the config discovery hint after a config failure", async () => {
    const blockModuleDirectory = "touch /root/.coder-modules";

    const output = await runPersonalize({ setup: blockModuleDirectory });

    expect(output.exitCode).toBe(0);
    expect(output.stderr.join("\n")).toContain(
      "Warning: failed to write personalize config file /root/.coder-modules/coder/personalize/config.",
    );
    expect(output.stdout.join("\n")).toContain("~/personalize.d");
    expect(output.stdout.join("\n")).not.toContain(
      "/root/.coder-modules/coder/personalize/config",
    );
  });

  it("warns when the personalize script is not executable", async () => {
    const setup = writeScriptCommand(
      "/root/personalize",
      printingScript("should-not-run"),
      { executable: false },
    );

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "🔐 Your personalize script isn't executable!",
    );
    expect(output.stdout).not.toContain("should-not-run");
    expect(output.stdout.join("\n")).toContain("~/personalize.d");
  });

  it("runs an executable personalize script without arguments", async () => {
    const setup = writeScriptCommand(
      "/root/personalize",
      "#!/bin/sh\nprintf 'personalize executed: %s\\n' \"$#\"\n",
    );

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["personalize executed: 0"]);
  });

  it.each([
    ["start", ["legacy", "custom start"]],
    ["stop", ["custom stop"]],
  ] as const)(
    "preserves spaces and shell syntax in a custom path at %s",
    async (phase, expectedStdout) => {
      const path = "/tmp/personalize scripts/$(printf injected) [daily]*";
      const setup = [
        writeScriptCommand(path, printingScript("legacy")),
        writeScriptCommand(
          `${path}.d/10 custom`,
          '#!/bin/sh\necho "custom $1"\n',
        ),
      ].join("\n");

      const output = await runPersonalize({ phase, path, setup });

      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual([...expectedStdout]);
    },
  );

  it("preserves the personalize script exit code and runs drop-ins after it fails", async () => {
    const setup = [
      writeScriptCommand("/root/personalize", exitingScript(23)),
      writeScriptCommand(
        "/root/personalize.d/10-later",
        printingScript("later"),
      ),
    ].join("\n");

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(23);
    expect(output.stderr.join("\n")).toContain("23");
    expect(output.stdout).toContain("later");
  });

  const utf8Locale = ["LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8"];
  const startOrder = ["legacy ", "10 start", "20 start", "A start", "a start"];
  const stopOrder = ["a stop", "A stop", "20 stop", "10 stop"];

  it.each([
    ["start", "alpine", "sh", [], startOrder],
    ["stop", "alpine", "sh", [], stopOrder],
    ["start", "codercom/example-base:ubuntu", "bash", utf8Locale, startOrder],
    ["stop", "codercom/example-base:ubuntu", "bash", utf8Locale, stopOrder],
  ] as const)(
    "runs eligible drop-in scripts in %s byte order in %s with %s",
    async (phase, image, shell, environment, expectedOrder) => {
      // Each script appends its name and first argument to /tmp/order.
      const appendToOrderFile = (name: string) =>
        `#!/bin/sh\nprintf '${name} %s\\n' "$1" >> /tmp/order\n`;
      const setup = [
        writeScriptCommand("/root/personalize", appendToOrderFile("legacy")),
        writeScriptCommand(
          "/root/personalize.d/20-last",
          appendToOrderFile("20"),
        ),
        writeScriptCommand(
          "/root/personalize.d/10 first.sh",
          appendToOrderFile("10"),
        ),
        writeScriptCommand(
          "/root/personalize.d/A-upper",
          appendToOrderFile("A"),
        ),
        writeScriptCommand(
          "/root/personalize.d/a-lower",
          appendToOrderFile("a"),
        ),
        writeScriptCommand(
          "/root/personalize.d/15-disabled",
          appendToOrderFile("bad"),
          { executable: false },
        ),
        writeScriptCommand(
          "/root/personalize.d/.hidden",
          appendToOrderFile("bad"),
        ),
        writeScriptCommand(
          "/root/personalize.d/25-backup~",
          appendToOrderFile("bad"),
        ),
        "mkdir -p /root/personalize.d/30-directory",
      ].join("\n");

      const output = await runPersonalize({
        phase,
        image,
        shell,
        environment,
        setup,
        inspect: "cat /tmp/order",
      });

      expect(output.exitCode).toBe(0);
      expect(output.inspection).toEqual([...expectedOrder]);
      expect(output.stdout.join("\n")).toContain("15-disabled");
    },
  );

  it.each([
    ["start", ["first", "last"]],
    ["stop", ["last", "first"]],
  ] as const)(
    "continues after a failing drop-in at %s and returns non-zero",
    async (phase, expectedStdout) => {
      const setup = [
        writeScriptCommand("/root/personalize", exitingScript(0)),
        writeScriptCommand(
          "/root/personalize.d/10-first",
          printingScript("first"),
        ),
        writeScriptCommand("/root/personalize.d/20-fail", exitingScript(17)),
        writeScriptCommand(
          "/root/personalize.d/30-last",
          printingScript("last"),
        ),
      ].join("\n");

      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(17);
      expect(output.stdout).toEqual([...expectedStdout]);
      expect(output.stderr.join("\n")).toContain("20-fail");
      expect(output.stderr.join("\n")).toContain("17");
    },
  );

  it.each(["start", "stop"])(
    "succeeds without a drop-in directory at %s",
    async (phase) => {
      const setup = writeScriptCommand("/root/personalize", exitingScript(0));

      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(0);
      expect(output.stderr).toEqual([""]);
    },
  );

  it.each([
    ["alpine", "sh"],
    ["debian:bookworm-slim", "dash"],
  ])("writes sourceable configuration in %s with %s", async (image, shell) => {
    const path = "/tmp/personalize scripts/'$(printf injected) [daily]*";
    const setup = writeScriptCommand(path, exitingScript(0));
    const printConfigAndCheckNoTemporaryFile = [
      '. "$HOME/.coder-modules/coder/personalize/config"',
      'printf "%s\\n" "$PERSONALIZE_PATH" "$PERSONALIZE_DIR" "$PERSONALIZE_LOG_DIR"',
      'test "$(find "$HOME/.coder-modules/coder/personalize" -name "config.*" | wc -l)" -eq 0',
    ].join("\n");

    const output = await runPersonalize({
      image,
      shell,
      path,
      setup,
      inspect: printConfigAndCheckNoTemporaryFile,
    });

    expect(output.exitCode).toBe(0);
    expect(output.inspection).toEqual([
      path,
      `${path}.d`,
      "/root/.coder-modules/coder/personalize/logs",
    ]);
  });

  it("round-trips an invalid UTF-8 byte followed by a quote in HOME on Alpine", async () => {
    const exportUnusualHome = String.raw`export HOME="$(printf "/tmp/personalize-\377'-home")"`;
    // env(1) runs a wrapper shell that sets HOME, then execs the test shell.
    const environment = [
      "LC_ALL=C.UTF-8",
      "sh",
      "-c",
      `${exportUnusualHome}; exec "$@"`,
      "sh",
    ];
    const setup = `${exportUnusualHome}\nmkdir -p "$HOME"`;
    const checkConfigMatchesHome = [
      "set -e",
      '. "$HOME/.coder-modules/coder/personalize/config"',
      'test "$PERSONALIZE_PATH" = "$HOME/personalize"',
      'test "$PERSONALIZE_DIR" = "$HOME/personalize.d"',
      'test "$PERSONALIZE_LOG_DIR" = "$HOME/.coder-modules/coder/personalize/logs"',
      'printf "config values match HOME\\n"',
    ].join("\n");

    const output = await runPersonalize({
      environment,
      setup,
      inspect: checkConfigMatchesHome,
    });

    expect(output.exitCode).toBe(0);
    expect(output.inspection).toEqual(["config values match HOME"]);
  });

  it("runs drop-in scripts without a personalize script", async () => {
    const setup = [
      writeScriptCommand(
        "/root/personalize.d/10-first",
        argumentPrintingScript("first"),
      ),
      writeScriptCommand(
        "/root/personalize.d/20-last",
        argumentPrintingScript("last"),
      ),
    ].join("\n");

    const output = await runPersonalize({ setup });

    expect(output.exitCode).toBe(0);
    expect(output.stdout.slice(-2)).toEqual(["first start", "last start"]);
  });

  for (const phase of ["start", "stop"]) {
    it.each([
      [
        "set",
        ["LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8"],
        "LC_ALL_SET=x VALUE=[en_US.UTF-8]",
      ],
      ["empty", ["LANG=en_US.UTF-8", "LC_ALL="], "LC_ALL_SET=x VALUE=[]"],
      ["unset", ["-u", "LC_ALL", "LANG=en_US.UTF-8"], "LC_ALL_SET= VALUE=[]"],
    ] as const)(
      `preserves the caller locale at ${phase} with %s LC_ALL in bash`,
      async (setting, environment, expectedLocaleLine) => {
        // Prints whether LC_ALL is set, its value, and how sort orders
        // mixed-case letters in the current locale.
        const printLocale = [
          'printf "LC_ALL_SET=%s VALUE=[%s]\\n" "${LC_ALL+x}" "${LC_ALL-}"',
          'printf "sorted=%s\\n" "$(printf "%s\\n" a A b B | sort | tr "\\n" ",")"',
        ].join("\n");
        const setup = [
          writeScriptCommand(
            "/root/personalize",
            `#!/usr/bin/env bash\n${printLocale}\n`,
          ),
          writeScriptCommand(
            "/root/personalize.d/10-locale",
            `#!/usr/bin/env bash\n${printLocale}\n`,
          ),
        ].join("\n");

        const output = await runPersonalize({
          phase,
          image: "codercom/example-base:ubuntu",
          shell: "bash",
          environment,
          setup,
          inspect: printLocale,
        });

        expect(output.exitCode).toBe(0);
        expect(output.inspection?.[0]).toBe(expectedLocaleLine);
        if (setting !== "empty") {
          expect(output.inspection?.[1]).toBe("sorted=a,A,b,B,");
        }
        // The personalize script and the drop-in script both print what the
        // caller sees; at stop only the drop-in script runs.
        expect(output.stdout).toEqual(
          phase === "start"
            ? [...output.inspection!, ...output.inspection!]
            : output.inspection!,
        );
      },
    );

    it.each([
      [
        "000",
        "mkdir -p /tmp/personalize.d; chmod 000 /tmp/personalize.d",
        "Skipping unreadable drop-in directory: /tmp/personalize.d",
      ],
      [
        "311",
        "mkdir -p /tmp/personalize.d; chmod 311 /tmp/personalize.d",
        "Skipping unreadable drop-in directory: /tmp/personalize.d",
      ],
      [
        "file",
        writeScriptCommand("/tmp/personalize.d", "not a directory", {
          executable: false,
        }),
        "Skipping non-directory drop-in path: /tmp/personalize.d",
      ],
    ])(
      `notices an unusable drop-in path once at ${phase}: %s`,
      async (_mode, createDropInPath, expectedNotice) => {
        const setup = [
          createUnprivilegedHome,
          writeScriptCommand("/tmp/personalize", exitingScript(0)),
          createDropInPath,
        ].join("\n");

        const output = await runPersonalize({
          phase,
          path: "/tmp/personalize",
          user: unprivilegedUser,
          environment: [`HOME=${unprivilegedHome}`],
          setup,
        });

        expect(output.exitCode).toBe(0);
        expect(output.stdout).toEqual([expectedNotice]);
      },
    );

    it(`notices broken drop-in script symlinks at ${phase}`, async () => {
      const setup = [
        writeScriptCommand("/root/personalize", exitingScript(0)),
        "mkdir -p /root/personalize.d; ln -s /missing /root/personalize.d/10-broken",
      ].join("\n");

      const output = await runPersonalize({ phase, setup });

      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual([
        "Skipping broken drop-in script symlink: /root/personalize.d/10-broken",
      ]);
    });
  }

  const unprivilegedModuleDir = `${unprivilegedHome}/.coder-modules/coder/personalize`;
  const noTemporaryConfigLeft = `test -z "$(find ${unprivilegedModuleDir} -name 'config.*' 2>/dev/null)"`;

  it.each([
    [
      "mkdir",
      `touch ${unprivilegedHome}/.coder-modules`,
      noTemporaryConfigLeft,
    ],
    [
      "temporary file",
      `mkdir -p ${unprivilegedModuleDir}; chmod 555 ${unprivilegedModuleDir}`,
      noTemporaryConfigLeft,
    ],
    [
      "rename",
      `mkdir -p ${unprivilegedModuleDir}; touch ${unprivilegedModuleDir}/config; chmod 1777 ${unprivilegedModuleDir}`,
      noTemporaryConfigLeft,
    ],
    [
      "config directory",
      `mkdir -p ${unprivilegedModuleDir}/config; chown -R ${unprivilegedUser} ${unprivilegedModuleDir}`,
      `test -d ${unprivilegedModuleDir}/config && ${noTemporaryConfigLeft}`,
    ],
  ])(
    "runs user scripts despite a config failure: %s",
    async (_failure, breakConfigWrite, inspect) => {
      const setup = [
        createUnprivilegedHome,
        writeScriptCommand("/tmp/personalize", printingScript("personalize")),
        writeScriptCommand(
          "/tmp/personalize.d/10-first",
          argumentPrintingScript("drop-in"),
        ),
        breakConfigWrite,
      ].join("\n");

      const output = await runPersonalize({
        path: "/tmp/personalize",
        user: unprivilegedUser,
        environment: [`HOME=${unprivilegedHome}`],
        setup,
        inspect,
      });

      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual(["personalize", "drop-in start"]);
      expect(output.stderr.join("\n")).toContain(
        `Warning: failed to write personalize config file ${unprivilegedModuleDir}/config.`,
      );
    },
  );

  it("resolves a relative path to an absolute config value", async () => {
    const setup = writeScriptCommand(
      "/personalize",
      printingScript("relative"),
    );
    const printConfiguredPath =
      '. "$HOME/.coder-modules/coder/personalize/config"; printf "%s\\n" "$PERSONALIZE_PATH"';

    const output = await runPersonalize({
      path: "personalize",
      setup,
      inspect: printConfiguredPath,
    });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["relative"]);
    expect(output.inspection).toEqual(["/personalize"]);
  });
});
