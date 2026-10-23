import { readFile } from "node:fs/promises";
import {
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  setDefaultTimeout,
} from "bun:test";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

setDefaultTimeout(120_000);

const IMAGE = "debian:bookworm-slim";
const STUB_PATH =
  "/stubs:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
const RELEASE_URL =
  "https://github.com/After-Certainty/pade/releases/download/v0.3.0";
const MODULE_DIR = "/root/.coder-modules/after-certainty/pade";
const SYNC_NAME = "after-certainty-pade-install_script";
const BINDINGS_PATH = "/root/.config/pade/coder-bindings.yaml";

const requiredVars = {
  agent_id: "foo",
  broker_endpoint: "https://broker.example.com",
  broker_capabilities: '["github.repo.read"]',
};

const CODER_STUB = `#!/bin/sh
[ "$1 $2" = "exp sync" ] || exit 1
case "$3" in start|complete) ;; *) exit 1 ;; esac
[ "$4" = "${SYNC_NAME}" ] || exit 1
echo "$@" >> /tmp/coder.log
`;

const renderedInstaller = (script: string) => {
  const encoded = script.match(
    /echo -n '([^']+)' \| base64 -d > .*\/scripts\/install\.sh/,
  );
  expect(encoded).not.toBeNull();
  return Buffer.from(encoded![1], "base64").toString();
};

// Serves release assets from /fixtures and records every requested URL.
const CURL_STUB = `#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry|--connect-timeout|--max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" >> /tmp/curl.log
src="/fixtures/$(basename "$url")"
[ -f "$src" ] || { echo "curl: (22) not found: $url" >&2; exit 22; }
cp "$src" "$out"
`;

const UNAME_STUB = `#!/bin/sh
case "$1" in
  -s) echo "\${FAKE_UNAME_S:-Linux}" ;;
  -m) echo "\${FAKE_UNAME_M:-x86_64}" ;;
  *) exec /usr/bin/uname "$@" ;;
esac
`;

const FIXTURES = `mkdir -p /fixtures
for arch in amd64 arm64; do
  dir="/build/$arch/pade-v0.3.0-linux-$arch"
  mkdir -p "$dir"
  cat > "$dir/pade" <<'EOF'
#!/bin/sh
echo "$@" >> /tmp/pade.log
echo "pade v0.3.0"
EOF
  chmod 0755 "$dir/pade"
  tar -czf "/fixtures/pade-v0.3.0-linux-$arch.tar.gz" -C "/build/$arch" .
done
cd /fixtures && sha256sum pade-*.tar.gz > SHA256SUMS
`;

let cleanupFunctions: (() => Promise<void>)[] = [];
afterEach(async () => {
  const cleanups = cleanupFunctions.reverse();
  cleanupFunctions = [];
  for (const cleanup of cleanups) {
    await cleanup();
  }
});

const setup = async (
  vars: Record<string, string> = {},
  customEnv: Record<string, string> = {},
) => {
  const state = await runTerraformApply(
    import.meta.dir,
    {
      ...requiredVars,
      ...vars,
    },
    customEnv,
  );
  const instance = findResourceInstance(
    state,
    "coder_script",
    "install_script",
  );
  const id = await runContainer(IMAGE);
  cleanupFunctions.push(() => removeContainer(id));

  // Each docker exec is slow on some hosts, so prepare the container in one call.
  const writeFile = (path: string, content: string, mode: string) =>
    `echo '${Buffer.from(content).toString("base64")}' | base64 -d > ${path} && chmod ${mode} ${path}`;
  const bootstrap = await execContainer(id, [
    "sh",
    "-c",
    [
      "set -eu",
      "mkdir -p /stubs",
      writeFile("/stubs/curl", CURL_STUB, "0755"),
      writeFile("/stubs/uname", UNAME_STUB, "0755"),
      writeFile("/stubs/coder", CODER_STUB, "0755"),
      writeFile("/tmp/run.sh", instance.script, "0644"),
      FIXTURES,
    ].join("\n"),
  ]);
  expect(bootstrap.stderr).toBe("");
  expect(bootstrap.exitCode).toBe(0);

  const run = (env: Record<string, string> = {}) =>
    execContainer(
      id,
      ["bash", "/tmp/run.sh"],
      [
        "-e",
        `PATH=${STUB_PATH}`,
        ...Object.entries(env).flatMap(([k, v]) => ["-e", `${k}=${v}`]),
      ],
    );
  const sh = (command: string) => execContainer(id, ["sh", "-c", command]);

  return { state, instance, id, run, sh };
};

describe("pade", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, requiredVars);

  it("uses only coder-utils install orchestration and preserves the rendered installer", async () => {
    const { state, instance, id, run, sh } = await setup();
    expect(
      state.resources
        .filter((resource) => resource.type === "coder_script")
        .map((resource) => [resource.module, resource.name]),
    ).toEqual([["module.coder_utils", "install_script"]]);
    expect(instance.agent_id).toBe(requiredVars.agent_id);
    expect(state.outputs.scripts.value).toEqual([SYNC_NAME]);
    const attributes = state.resources.find(
      (resource) => resource.type === "coder_script",
    )!.instances[0].attributes;
    expect(attributes.display_name).toBe("PADE: Install Script");
    expect(attributes.run_on_start).toBe(true);
    expect(attributes.start_blocks_login).toBe(false);
    const template = await readFile(
      `${import.meta.dir}/scripts/install.sh.tftpl`,
      "utf8",
    );
    const bindings = Buffer.from(
      renderedInstaller(instance.script).match(/^BINDINGS_B64='([^']*)'$/m)![1],
      "base64",
    ).toString();
    expect(renderedInstaller(instance.script)).toBe(
      template
        .replace("${PADE_VERSION}", "v0.3.0")
        .replace("${BINDINGS_B64}", Buffer.from(bindings).toString("base64")),
    );
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(
      await readFileContainer(id, `${MODULE_DIR}/scripts/install.sh`),
    ).toBe(renderedInstaller(instance.script));
    expect(await readFileContainer(id, `${MODULE_DIR}/logs/install.log`)).toBe(
      result.stdout,
    );
    expect((await sh("cat /tmp/coder.log")).stdout.trim().split("\n")).toEqual([
      `exp sync start ${SYNC_NAME}`,
      `exp sync complete ${SYNC_NAME}`,
    ]);
  });

  it("installs the amd64 release and runs pade --version", async () => {
    const { run, sh } = await setup();
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("installing PADE v0.3.0 (linux/amd64)");
    expect(result.stdout).toContain("pade v0.3.0");

    const requested = await sh("cat /tmp/curl.log");
    expect(requested.stdout.trim().split("\n")).toEqual([
      `${RELEASE_URL}/pade-v0.3.0-linux-amd64.tar.gz`,
      `${RELEASE_URL}/SHA256SUMS`,
    ]);

    const invocations = await sh("cat /tmp/pade.log");
    expect(invocations.stdout.trim()).toBe("--version");

    const mode = await sh("stat -c %a /root/.local/bin/pade");
    expect(mode.stdout.trim()).toBe("755");
  });

  it("selects the arm64 release on aarch64", async () => {
    const { run, sh } = await setup();
    const result = await run({ FAKE_UNAME_M: "aarch64" });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("(linux/arm64)");

    const requested = await sh("head -n 1 /tmp/curl.log");
    expect(requested.stdout.trim()).toBe(
      `${RELEASE_URL}/pade-v0.3.0-linux-arm64.tar.gz`,
    );
  });

  it("installs the requested pade_version", async () => {
    const { run, sh } = await setup({ pade_version: "0.4.0" });
    const fixtures = await sh(`cd /fixtures
cp pade-v0.3.0-linux-amd64.tar.gz pade-v0.4.0-linux-amd64.tar.gz
sha256sum pade-v0.4.0-linux-amd64.tar.gz >> SHA256SUMS`);
    expect(fixtures.exitCode).toBe(0);
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("installing PADE v0.4.0 (linux/amd64)");

    const requested = await sh("cat /tmp/curl.log");
    expect(requested.stdout.trim().split("\n")).toEqual([
      "https://github.com/After-Certainty/pade/releases/download/v0.4.0/pade-v0.4.0-linux-amd64.tar.gz",
      "https://github.com/After-Certainty/pade/releases/download/v0.4.0/SHA256SUMS",
    ]);
  });

  it("rejects unsupported architectures before downloading", async () => {
    const { run, sh } = await setup();
    const result = await run({ FAKE_UNAME_M: "riscv64" });
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "unsupported workspace architecture: riscv64",
    );
    expect((await sh("test -e /tmp/curl.log")).exitCode).not.toBe(0);
  });

  it("rejects non-Linux workspaces before downloading", async () => {
    const { run, sh } = await setup();
    const result = await run({ FAKE_UNAME_S: "Darwin" });
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "Linux workspaces are required",
    );
    expect((await sh("test -e /tmp/curl.log")).exitCode).not.toBe(0);
  });

  it("fails on a checksum mismatch without installing", async () => {
    const { run, sh } = await setup();
    await sh(
      "sed -i 's/^[0-9a-f]*\\(  pade-v0.3.0-linux-amd64\\)/0000000000000000000000000000000000000000000000000000000000000000\\1/' /fixtures/SHA256SUMS",
    );
    const result = await run();
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain("FAILED");
    expect((await sh("test -e /root/.local/bin/pade")).exitCode).not.toBe(0);
    expect((await sh(`test -e ${BINDINGS_PATH}`)).exitCode).not.toBe(0);
  });

  it("fails when the asset is missing from SHA256SUMS", async () => {
    const { run, sh } = await setup();
    await sh("sed -i '/linux-amd64/d' /fixtures/SHA256SUMS");
    const result = await run();
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "release checksum does not contain pade-v0.3.0-linux-amd64.tar.gz",
    );
    expect((await sh("test -e /root/.local/bin/pade")).exitCode).not.toBe(0);
  });

  it("writes only the requested broker bindings", async () => {
    const { id, run, sh } = await setup({
      broker_endpoint: "https://other-broker.example.com",
      broker_audience: "pade-broker",
      broker_identity: "cursor",
      broker_capabilities: '["github.repo.read", "example.capability"]',
    });
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain(
      `broker bindings written to ${BINDINGS_PATH}`,
    );

    const mode = await sh(`stat -c %a ${BINDINGS_PATH}`);
    expect(mode.stdout.trim()).toBe("600");

    const broker = {
      endpoint: "https://other-broker.example.com",
      audience: "pade-broker",
      identity: "cursor",
    };
    const bindings = Bun.YAML.parse(await readFileContainer(id, BINDINGS_PATH));
    expect(bindings).toEqual({
      version: "0.1",
      capabilities: {
        "github.repo.read": { provider: "broker", broker },
        "example.capability": { provider: "broker", broker },
      },
    });
  });

  it("configures shell startup files idempotently", async () => {
    const { run, sh } = await setup();
    await sh(
      "mkdir -p /root/.config/fish && touch /root/.bashrc /root/.zshrc /root/.config/fish/config.fish && rm -f /root/.bash_profile /root/.zprofile",
    );
    expect((await run()).exitCode).toBe(0);
    expect((await run()).exitCode).toBe(0);

    const counts = await sh(`cd /root
for f in .profile .bashrc .zshrc; do
  echo "$f path $(grep -cxF 'export PATH="$HOME/.local/bin:$PATH"' "$f")"
  echo "$f bindings $(grep -cxF 'export PADE_BINDINGS="$HOME/.config/pade/coder-bindings.yaml"' "$f")"
done
f=.config/fish/config.fish
echo "fish path $(grep -cxF 'fish_add_path $HOME/.local/bin' "$f")"
echo "fish bindings $(grep -cxF 'set -gx PADE_BINDINGS $HOME/.config/pade/coder-bindings.yaml' "$f")"
for f in .bash_profile .zprofile; do
  if [ -e "$f" ]; then echo "$f created"; fi
done`);
    expect(counts.stdout.trim().split("\n")).toEqual([
      ".profile path 1",
      ".profile bindings 1",
      ".bashrc path 1",
      ".bashrc bindings 1",
      ".zshrc path 1",
      ".zshrc bindings 1",
      "fish path 1",
      "fish bindings 1",
    ]);

    const login = await sh(
      "env -i HOME=/root PATH=/usr/bin:/bin bash -lc 'command -v pade && echo \"$PADE_BINDINGS\"'",
    );
    expect(login.stdout.trim().split("\n")).toEqual([
      "/root/.local/bin/pade",
      BINDINGS_PATH,
    ]);
  });

  it("keeps credential material out of state and the installer", async () => {
    const coderSession = "test-only-coder-session-token";
    const { state, instance, id, run } = await setup(
      {},
      {
        CODER_WORKSPACE_OWNER_SESSION_TOKEN: coderSession,
      },
    );
    const credentialPattern =
      /token|secret|password|private key|ghp_|github_pat_|gho_|ghs_/i;
    const installer = renderedInstaller(instance.script);
    expect(instance.script).not.toMatch(credentialPattern);
    expect(installer).not.toMatch(credentialPattern);
    // Upstream coder-utils reads owner metadata, including Coder's existing
    // control-plane session token. Allow only that exact fixture in that field;
    // it must never reach the PADE script, bindings, logs, or other state.
    const checkValues = (value: unknown): void => {
      if (typeof value === "string")
        expect(value).not.toMatch(credentialPattern);
      else if (Array.isArray(value)) value.forEach(checkValues);
      else if (value && typeof value === "object")
        Object.values(value).forEach(checkValues);
    };
    const owner = state.resources.find(
      (resource) =>
        resource.module === "module.coder_utils" &&
        resource.mode === "data" &&
        resource.type === "coder_workspace_owner",
    );
    expect(owner).toBeDefined();
    expect(owner!.instances[0].attributes.session_token).toBe(coderSession);
    for (const resource of state.resources) {
      for (const instance of resource.instances) {
        const { session_token, ...attributes } = instance.attributes;
        if (resource === owner) {
          expect(session_token).toBe(coderSession);
          expect(attributes.ssh_private_key).toBe("");
          if ("oidc_access_token" in attributes)
            expect(attributes.oidc_access_token).toBe("");
        } else checkValues(session_token);
        checkValues(attributes);
      }
    }
    checkValues(state.outputs);
    expect((await run()).exitCode).toBe(0);
    expect(
      await readFileContainer(id, `${MODULE_DIR}/scripts/install.sh`),
    ).toBe(installer);
    expect(
      await readFileContainer(id, `${MODULE_DIR}/logs/install.log`),
    ).not.toMatch(credentialPattern);

    const embedded = installer.match(/^BINDINGS_B64='([^']*)'$/m);
    expect(embedded).not.toBeNull();
    const bindings = Bun.YAML.parse(
      Buffer.from(embedded![1], "base64").toString(),
    );
    expect(bindings).toEqual({
      version: "0.1",
      capabilities: {
        "github.repo.read": {
          provider: "broker",
          broker: {
            endpoint: "https://broker.example.com",
            audience: "https://broker.example.com",
            identity: "gce",
          },
        },
      },
    });
  });
});
