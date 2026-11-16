import {
  afterAll,
  beforeAll,
  describe,
  expect,
  it,
  setDefaultTimeout,
} from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
} from "~test";

setDefaultTimeout(120_000);
const commit = "a".repeat(40);
const root = "/root/.coder-modules/coder/vscode-web";
let container: string;

beforeAll(async () => {
  await runTerraformInit(import.meta.dir);
  container = await runContainer("ubuntu:22.04");
  const setup = await execContainer(container, [
    "bash",
    "-ec",
    `
apt-get update -qq
apt-get install -y -qq unzip libarchive-tools
ln -sf /usr/bin/bsdtar /usr/bin/tar
cat > /usr/local/bin/coder <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > /usr/local/bin/uname <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -s ]; then echo Darwin; else cat /root/architecture; fi
EOF
cat > /usr/local/bin/curl <<'EOF'
#!/usr/bin/env bash
set -eu
url="$2"
echo "$url" >> /root/downloads
case "$url" in
  */api/commits/*) printf '["${commit}"]'; exit 0 ;;
  */cli-darwin-*) cp /root/cli.zip "$4" ;;
  */server-darwin*) cp /root/server.zip "$4" ;;
  *) echo "Unexpected URL: $url" >&2; exit 22 ;;
esac
EOF
chmod +x /usr/local/bin/coder /usr/local/bin/uname /usr/local/bin/curl
`,
  ]);
  expect(setup.exitCode, setup.stderr + setup.stdout).toBe(0);
});
afterAll(async () => {
  if (container) await removeContainer(container);
});

// Real ZIP extraction with BSD tar; only platform detection, downloads and
// executable payloads are doubled. Native macOS runtime is a separate check.
describe("vscode-web macOS archives", () => {
  for (const scenario of [
    { arch: "arm64", platform: "darwin-arm64", corrupt: "" },
    { arch: "x86_64", platform: "darwin", corrupt: "" },
    { arch: "arm64", platform: "darwin-arm64", corrupt: "cli" },
    { arch: "arm64", platform: "darwin-arm64", corrupt: "server" },
  ]) {
    it(`${scenario.arch}: ${scenario.corrupt ? `rejects invalid ${scenario.corrupt} ZIP` : "extracts CLI and server ZIP archives"}`, async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        use_cli: true,
      });
      const setup = await execContainer(container, [
        "bash",
        "-ec",
        `
rm -rf '${root}' /root/archive-fixtures /root/downloads
printf '%s' '${scenario.arch}' > /root/architecture
mkdir -p /root/archive-fixtures/cli /root/archive-fixtures/server/vscode-server-${scenario.platform}-web/bin
printf '#!/usr/bin/env bash\necho test-cli\n' > /root/archive-fixtures/cli/code
printf '#!/usr/bin/env bash\nexit 0\n' > /root/archive-fixtures/server/vscode-server-${scenario.platform}-web/bin/code-server
chmod +x /root/archive-fixtures/cli/code /root/archive-fixtures/server/vscode-server-${scenario.platform}-web/bin/code-server
bsdtar -a -cf /root/cli.zip -C /root/archive-fixtures/cli code
bsdtar -a -cf /root/server.zip -C /root/archive-fixtures/server vscode-server-${scenario.platform}-web
${scenario.corrupt ? `printf 'invalid archive' > /root/${scenario.corrupt}.zip` : ""}
`,
      ]);
      expect(setup.exitCode, setup.stderr + setup.stdout).toBe(0);
      const install = await execContainer(container, [
        "bash",
        "-c",
        findResourceInstance(state, "coder_script", "install_script").script,
      ]);
      const marker = await execContainer(container, ["cat", `${root}/commit`]);
      if (scenario.corrupt) {
        expect(install.exitCode).not.toBe(0);
        expect(marker.exitCode).not.toBe(0);
        return;
      }
      expect(install.exitCode, install.stderr + install.stdout).toBe(0);
      expect(marker.stdout.trim()).toBe(commit);
      const executables = await execContainer(container, [
        "bash",
        "-ec",
        `test -x '${root}/bin/code-${commit}'; test -x '${root}/cli/serve-web/${commit}/bin/code-server'`,
      ]);
      expect(executables.exitCode).toBe(0);
      const downloads = await execContainer(container, [
        "cat",
        "/root/downloads",
      ]);
      expect(downloads.stdout).toContain(
        `/api/commits/stable/server-${scenario.platform}-web`,
      );
      expect(downloads.stdout).toContain(
        `/cli-darwin-${scenario.arch === "arm64" ? "arm64" : "x64"}/stable`,
      );
      expect(downloads.stdout).toContain(
        `/server-${scenario.platform}-web/stable`,
      );
      expect(downloads.stdout).not.toContain("server-darwin-x64-web");
    });
  }
});
