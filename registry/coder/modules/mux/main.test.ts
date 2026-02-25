import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("mux", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("runs with default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add --no-cache bash tar gzip ca-certificates findutils nodejs && update-ca-certificates",
    );
    if (output.exitCode !== 0) {
      console.log("STDOUT:\n" + output.stdout.join("\n"));
      console.log("STDERR:\n" + output.stderr.join("\n"));
    }
    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📥 npm not found; downloading tarball from npm registry...",
      "🥳 mux has been installed in /tmp/mux",
      "🚀 Starting mux server on port 4000...",
      "Check logs at /tmp/mux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 60000);

  it("parses custom additional_arguments", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      log_path: "/tmp/mux.log",
      additional_arguments:
        "--open-mode pinned --add-project '/workspaces/my repo'",
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/curl");

    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash >/dev/null
mkdir -p /tmp/mux
cat <<'EOF' > /tmp/mux/mux
#!/usr/bin/env sh
i=1
for arg in "$@"; do
  echo "arg$i=$arg"
  i=$((i + 1))
done
EOF
chmod +x /tmp/mux/mux`,
      ]);
      expect(setup.exitCode).toBe(0);

      const output = await execContainer(id, ["sh", "-c", instance.script]);
      if (output.exitCode !== 0) {
        console.log("STDOUT:\n" + output.stdout);
        console.log("STDERR:\n" + output.stderr);
      }
      expect(output.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 1"]);
      const log = await readFileContainer(id, "/tmp/mux.log");
      expect(log).toContain("arg1=server");
      expect(log).toContain("arg2=--port");
      expect(log).toContain("arg3=4000");
      expect(log).toContain("arg4=--open-mode");
      expect(log).toContain("arg5=pinned");
      expect(log).toContain("arg6=--add-project");
      expect(log).toContain("arg7=/workspaces/my repo");
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("runs with npm present", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeScriptInContainer(
      state,
      "node:20-alpine",
      "sh",
      "apk add bash",
    );

    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📦 Installing mux via npm into /tmp/mux...",
      "⏭️  Skipping npm lifecycle scripts with --ignore-scripts",
      "🥳 mux has been installed in /tmp/mux",
      "🚀 Starting mux server on port 4000...",
      "Check logs at /tmp/mux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 180000);
});
