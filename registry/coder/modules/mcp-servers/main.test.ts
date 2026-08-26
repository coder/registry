import { beforeAll, describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const clients = JSON.stringify(["claude code", "codex"]);
setDefaultTimeout(30 * 1000);

const mockCommands = `
mkdir -p /usr/local/bin
cat > /usr/local/bin/coder <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /usr/local/bin/node <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo v22.23.2
fi
EOF
cat > /usr/local/bin/npx <<'EOF'
#!/bin/sh
printf 'npx %s\\n' "$*"
EOF
chmod +x /usr/local/bin/coder /usr/local/bin/node /usr/local/bin/npx
`;

describe("mcp-servers", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
    clients,
  });

  it("does not invoke mcp-add when no server is selected", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients,
    });

    const output = await executeScriptInContainer(
      state,
      "ubuntu:24.04",
      "bash",
      mockCommands,
    );

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain("No MCP servers selected.");
    expect(output.stdout.join("\n")).not.toContain("mcp-add@");
  });

  it("configures every selected official server for all clients", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients,
      default: JSON.stringify(["github", "playwright"]),
    });

    const output = await executeScriptInContainer(
      state,
      "ubuntu:24.04",
      "bash",
      mockCommands,
    );
    const stdout = output.stdout.join("\n");

    expect(output.exitCode).toBe(0);
    expect(stdout).toContain(
      "mcp-add@0.2.4 --name github --type http --url https://api.githubcopilot.com/mcp/ --scope global --clients claude code,codex",
    );
    expect(stdout).toContain(
      "mcp-add@0.2.4 --name playwright --type stdio --command npx --yes @playwright/mcp@0.0.79 --headless --scope global --clients claude code,codex",
    );
  });
});
