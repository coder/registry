import { beforeAll, describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type TerraformState,
} from "~test";

setDefaultTimeout(60 * 1000);

const clients = JSON.stringify(["claude code", "codex", "cursor"]);
const github = JSON.stringify(["github"]);

const mockCommands = `
mkdir -p /usr/local/bin "$HOME/.cursor" "$HOME/.codex"
cat > /usr/local/bin/coder <<'EOF'
#!/bin/sh
if [ "$1" = "external-auth" ] && [ "$2" = "access-token" ]; then
  printf '%s\n' 'dynamic-test-token'
fi
exit 0
EOF
cat > /usr/local/bin/codex <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/codex-calls
exit 0
EOF
cat > /usr/local/bin/npx <<'EOF'
#!/bin/sh
printf 'npx %s\\n' "$*"
EOF
cat > /usr/local/bin/docker <<'EOF'
#!/bin/sh
printf 'docker %s\\n' "$*"
EOF
chmod +x /usr/local/bin/coder /usr/local/bin/codex /usr/local/bin/docker /usr/local/bin/npx
printf '%s\n' '{"mcpServers":{"github":{"type":"http","url":"https://api.githubcopilot.com/mcp/"}}}' > "$HOME/.claude.json"
cp "$HOME/.claude.json" "$HOME/.cursor/mcp.json"
printf '%s\n' '[mcp_servers.github]' 'url = "https://api.githubcopilot.com/mcp/"' > "$HOME/.codex/config.toml"
`;

async function executePipeline(
  state: TerraformState,
  options: { after?: string; beforeAuth?: string; env?: string[] } = {},
) {
  const container = await runContainer("node:22-bookworm");
  const output: string[] = [];

  try {
    const setup = await execContainer(container, ["bash", "-c", mockCommands]);
    expect(setup.exitCode).toBe(0);
    if (options.beforeAuth) {
      const preparation = await execContainer(container, [
        "bash",
        "-c",
        options.beforeAuth,
      ]);
      expect(preparation.exitCode).toBe(0);
    }
    for (const name of ["install_script", "post_install_script"]) {
      const script = findResourceInstance(state, "coder_script", name).script;
      const result = await execContainer(
        container,
        ["bash", "-c", script],
        options.env?.flatMap((value) => ["--env", value]),
      );
      output.push(result.stdout, result.stderr);
      if (result.exitCode !== 0) {
        return { exitCode: result.exitCode, output: output.join("\n") };
      }
    }
    if (options.after) {
      const result = await execContainer(container, [
        "bash",
        "-c",
        options.after,
      ]);
      output.push(result.stdout, result.stderr);
      return { exitCode: result.exitCode, output: output.join("\n") };
    }
    return { exitCode: 0, output: output.join("\n") };
  } finally {
    await removeContainer(container);
  }
}

describe("mcp-servers authentication", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  it("renders the exact baseline install script for explicit mode none", async () => {
    const variables = { agent_id: "test-agent", clients, default: github };
    const [implicit, explicit] = await Promise.all([
      runTerraformApply(import.meta.dir, variables),
      runTerraformApply(import.meta.dir, {
        ...variables,
        github_auth: JSON.stringify({ mode: "none" }),
      }),
    ]);

    expect(
      findResourceInstance(explicit, "coder_script", "install_script").script,
    ).toBe(
      findResourceInstance(implicit, "coder_script", "install_script").script,
    );
    expect(
      explicit.resources.some((item) => item.name === "post_install_script"),
    ).toBeFalse();
  });

  it("configures token references without writing the token value", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients,
      default: github,
      github_auth: JSON.stringify({
        mode: "token-env",
        token_env_var: "WORKSPACE_GITHUB_TOKEN",
      }),
    });
    const result = await executePipeline(state, {
      env: ["WORKSPACE_GITHUB_TOKEN=super-secret-test-value"],
      after: `
set -e
node - <<'NODE'
const fs = require("node:fs");
const claude = JSON.parse(fs.readFileSync(process.env.HOME + "/.claude.json"));
const cursor = JSON.parse(fs.readFileSync(process.env.HOME + "/.cursor/mcp.json"));
if (claude.mcpServers.github.headers.Authorization !== "Bearer \${WORKSPACE_GITHUB_TOKEN}") process.exit(1);
if (cursor.mcpServers.github.headers.Authorization !== "Bearer \${env:WORKSPACE_GITHUB_TOKEN}") process.exit(1);
NODE
grep -q -- '--bearer-token-env-var WORKSPACE_GITHUB_TOKEN' /tmp/codex-calls
! grep -R 'super-secret-test-value' "$HOME/.claude.json" "$HOME/.cursor/mcp.json" "$HOME/.codex/config.toml" /tmp/codex-calls
`,
    });

    expect(result.exitCode).toBe(0);
    expect(result.output).not.toContain("super-secret-test-value");
    expect(result.output).toContain("no token value was written");
  });

  it("fails explicitly when the token environment variable is missing", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients,
      default: github,
      github_auth: JSON.stringify({
        mode: "token-env",
        token_env_var: "WORKSPACE_GITHUB_TOKEN",
      }),
    });
    const result = await executePipeline(state);

    expect(result.exitCode).not.toBe(0);
    expect(result.output).toContain(
      "requires the WORKSPACE_GITHUB_TOKEN environment variable",
    );
    expect(result.output).not.toContain("no token value was written");
  });

  it("resolves external auth only through Claude's runtime helper", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients: JSON.stringify(["claude code"]),
      default: github,
      github_auth: JSON.stringify({
        mode: "external-auth",
        external_auth_id: "primary-github",
      }),
    });
    const result = await executePipeline(state, {
      after: `
set -e
helper="$HOME/.coder-modules/coder-labs/mcp-servers/scripts/github-headers.sh"
"$helper" > /tmp/github-headers.json
node -e 'const h=require("/tmp/github-headers.json");if(h.Authorization!=="Bearer dynamic-test-token")process.exit(1)'
rm /tmp/github-headers.json
grep -q 'headersHelper' "$HOME/.claude.json"
! grep -R 'dynamic-test-token' "$helper" "$HOME/.claude.json"
`,
    });

    expect(result.exitCode).toBe(0);
    expect(result.output).not.toContain("dynamic-test-token");
    expect(result.output).toContain("primary-github");
  });

  it("reports the external auth action when the provider is not connected", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients: JSON.stringify(["claude code"]),
      default: github,
      github_auth: JSON.stringify({ mode: "external-auth" }),
    });
    const result = await executePipeline(state, {
      beforeAuth: `cat > /usr/local/bin/coder <<'EOF'
#!/bin/sh
if [ "$1" = "external-auth" ] && [ "$2" = "access-token" ]; then
  printf '%s' 'https://coder.example/external-auth/github'
  exit 1
fi
exit 0
EOF
chmod +x /usr/local/bin/coder`,
      after: `"$HOME/.coder-modules/coder-labs/mcp-servers/scripts/github-headers.sh"`,
    });
    expect(result.exitCode).not.toBe(0);
    expect(result.output).toContain("Authenticate at: https://coder.example");
    expect(result.output).not.toContain("dynamic-test-token");
  });

  it("pins native OAuth to the official image and loopback callback", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      clients,
      default: github,
      github_auth: JSON.stringify({ mode: "native-oauth" }),
    });
    const result = await executePipeline(state);

    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("-p 127.0.0.1:8085:8085");
    expect(result.output).toContain(
      "github-mcp-server:v1.11.0@sha256:fbec75de11c255213fa08d80fb166abe73d851fff631c51c0079872967720699",
    );
    expect(result.output).not.toContain("PERSONAL_ACCESS_TOKEN");
  });

  it("skips user authentication while the workspace owner is prebuilds", async () => {
    const state = await runTerraformApply(
      import.meta.dir,
      {
        agent_id: "test-agent",
        clients: JSON.stringify(["claude code"]),
        default: github,
        github_auth: JSON.stringify({ mode: "external-auth" }),
      },
      { CODER_WORKSPACE_OWNER: "prebuilds" },
    );
    const result = await executePipeline(state);

    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("after claim");
    expect(result.output).not.toContain("dynamic-test-token");
  });
});
