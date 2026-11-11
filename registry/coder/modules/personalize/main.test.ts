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
  environment = [] as string[],
  user = "root",
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
      const setup = await execContainer(
        id,
        [shell, "-c", before],
        ["--user", "root"],
      );
      expect(setup.exitCode, setup.stderr).toBe(0);
    }
    const output = await execContainer(
      id,
      ["env", ...environment, shell, "-c", script],
      ["--user", user],
    );
    const inspection = after
      ? await execContainer(
          id,
          ["env", ...environment, shell, "-c", after],
          ["--user", user],
        )
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
    const output = await executePersonalize({
      before: "touch /root/.coder-modules",
    });
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

  it.each([
    ["start", "alpine", "sh"],
    ["stop", "alpine", "sh"],
    ["start", "codercom/example-base:ubuntu", "bash"],
    ["stop", "codercom/example-base:ubuntu", "bash"],
  ])(
    "runs eligible drop-in scripts in %s byte order in %s with %s",
    async (phase, image, shell) => {
      const record = (name: string) =>
        `#!/bin/sh\nprintf '${name} %s\\n' "$1" >> /tmp/order\n`;
      const output = await executePersonalize({
        phase,
        image,
        shell,
        environment:
          shell === "bash" ? ["LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8"] : [],
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
      expect(output.exitCode).toBe(17);
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
    ["alpine", "sh"],
    ["debian:bookworm-slim", "dash"],
  ])("writes sourceable configuration in %s with %s", async (image, shell) => {
    const path = "/tmp/personalize scripts/'$(printf injected) [daily]*";
    const output = await executePersonalize({
      image,
      shell,
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
  });

  it("round-trips an invalid UTF-8 byte followed by a quote in HOME on Alpine", async () => {
    const home = String.raw`export HOME="$(printf "/tmp/personalize-\377'-home")"`;
    const output = await executePersonalize({
      environment: ["LC_ALL=C.UTF-8", "sh", "-c", `${home}; exec "$@"`, "sh"],
      before: `${home}\nmkdir -p "$HOME"`,
      after: [
        "set -e",
        '. "$HOME/.coder-modules/coder/personalize/config"',
        'test "$PERSONALIZE_PATH" = "$HOME/personalize"',
        'test "$PERSONALIZE_DIR" = "$HOME/personalize.d"',
        'test "$PERSONALIZE_LOG_DIR" = "$HOME/.coder-modules/coder/personalize/logs"',
        'printf "config values match HOME\\n"',
      ].join("\n"),
    });
    expect(output.exitCode).toBe(0);
    expect(output.inspection).toEqual(["config values match HOME"]);
  });

  it("runs drop-in scripts without a personalize script", async () => {
    const output = await executePersonalize({
      before: [
        createScript(
          "/root/personalize.d/10-first",
          '#!/bin/sh\nprintf "first %s\\n" "$1"\n',
        ),
        createScript(
          "/root/personalize.d/20-last",
          '#!/bin/sh\nprintf "last %s\\n" "$1"\n',
        ),
      ].join("\n"),
    });
    expect(output.exitCode).toBe(0);
    expect(output.stdout.slice(-2)).toEqual(["first start", "last start"]);
  });

  for (const phase of ["start", "stop"]) {
    it.each(["set", "empty", "unset"])(
      `preserves the caller locale at ${phase} with %s LC_ALL in bash`,
      async (setting) => {
        const probe = [
          'printf "LC_ALL_SET=%s VALUE=[%s]\\n" "${LC_ALL+x}" "${LC_ALL-}"',
          'printf "sorted=%s\\n" "$(printf "%s\\n" a A b B | sort | tr "\\n" ",")"',
        ].join("\n");
        const environment =
          setting === "unset"
            ? ["-u", "LC_ALL", "LANG=en_US.UTF-8"]
            : [
                "LANG=en_US.UTF-8",
                `LC_ALL=${setting === "set" ? "en_US.UTF-8" : ""}`,
              ];
        const output = await executePersonalize({
          phase,
          image: "codercom/example-base:ubuntu",
          shell: "bash",
          environment,
          before: [
            createScript(
              "/root/personalize",
              `#!/usr/bin/env bash\n${probe}\n`,
            ),
            createScript(
              "/root/personalize.d/10-locale",
              `#!/usr/bin/env bash\n${probe}\n`,
            ),
          ].join("\n"),
          after: probe,
        });
        expect(output.exitCode).toBe(0);
        expect(output.inspection?.[0]).toBe(
          `LC_ALL_SET=${setting === "unset" ? "" : "x"} VALUE=[${setting === "set" ? "en_US.UTF-8" : ""}]`,
        );
        if (setting !== "empty") {
          expect(output.inspection?.[1]).toBe("sorted=a,A,b,B,");
        }
        expect(output.stdout).toEqual(
          phase === "start"
            ? [...output.inspection!, ...output.inspection!]
            : output.inspection,
        );
      },
    );

    it.each(["000", "311", "file"])(
      `notices an unusable drop-in path once at ${phase}: %s`,
      async (mode) => {
        const output = await executePersonalize({
          phase,
          path: "/tmp/personalize",
          user: "65534:65534",
          environment: ["HOME=/tmp/personalize-home"],
          before: [
            "mkdir -p /tmp/personalize-home; chown 65534:65534 /tmp/personalize-home",
            createScript("/tmp/personalize", "#!/bin/sh\nexit 0\n"),
            mode === "file"
              ? createScript("/tmp/personalize.d", "not a directory", false)
              : `mkdir -p /tmp/personalize.d; chmod ${mode} /tmp/personalize.d`,
          ].join("\n"),
        });
        expect(output.exitCode).toBe(0);
        expect(output.stdout).toEqual([
          mode === "file"
            ? "Skipping non-directory drop-in path: /tmp/personalize.d"
            : "Skipping unreadable drop-in directory: /tmp/personalize.d",
        ]);
      },
    );

    it(`notices broken drop-in script symlinks at ${phase}`, async () => {
      const output = await executePersonalize({
        phase,
        before: [
          createScript("/root/personalize", "#!/bin/sh\nexit 0\n"),
          "mkdir -p /root/personalize.d; ln -s /missing /root/personalize.d/10-broken",
        ].join("\n"),
      });
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual([
        "Skipping broken drop-in script symlink: /root/personalize.d/10-broken",
      ]);
    });
  }

  it.each(["mkdir", "temporary file", "rename"])(
    "runs user scripts despite a config failure: %s",
    async (failure) => {
      const root = "/tmp/personalize-home/.coder-modules/coder/personalize";
      const output = await executePersonalize({
        path: "/tmp/personalize",
        user: "65534:65534",
        environment: ["HOME=/tmp/personalize-home"],
        before: [
          "mkdir -p /tmp/personalize-home; chown 65534:65534 /tmp/personalize-home",
          createScript("/tmp/personalize", "#!/bin/sh\necho personalize\n"),
          createScript(
            "/tmp/personalize.d/10-first",
            '#!/bin/sh\nprintf "drop-in %s\\n" "$1"\n',
          ),
          failure === "mkdir"
            ? "touch /tmp/personalize-home/.coder-modules"
            : failure === "temporary file"
              ? `mkdir -p ${root}; chmod 555 ${root}`
              : `mkdir -p ${root}/config; chown 65534:65534 ${root}; chmod 000 ${root}/config`,
        ].join("\n"),
        after: `test -z "$(find ${root} -maxdepth 1 -name 'config.*' 2>/dev/null)"`,
      });
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toEqual(["personalize", "drop-in start"]);
      expect(output.stderr.join("\n")).toContain(
        `Warning: failed to write personalize config file ${root}/config.`,
      );
    },
  );

  it("resolves a relative path to an absolute config value", async () => {
    const output = await executePersonalize({
      path: "personalize",
      before: createScript("/personalize", "#!/bin/sh\necho relative\n"),
      after:
        '. "$HOME/.coder-modules/coder/personalize/config"; printf "%s\\n" "$PERSONALIZE_PATH"',
    });
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["relative"]);
    expect(output.inspection).toEqual(["/personalize"]);
  });
});
