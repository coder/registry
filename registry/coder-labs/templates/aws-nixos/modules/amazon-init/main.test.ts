import { expect, it } from "bun:test";
import { readFile } from "node:fs/promises";
import { execContainer, removeContainer, runContainer } from "~test";

it("agent can create its binary directory without owning the root handoff directory", async () => {
  const bootstrap = await readFile(
    new URL("./scripts/start-agent.sh.tftpl", import.meta.url),
    "utf8",
  );
  const handoff = bootstrap.match(/^chown_handoff\(\) \{[\s\S]*?^\}/m)?.[0];
  expect(handoff).toBeDefined();
  const container = await runContainer("ubuntu:24.04");
  try {
    const result = await execContainer(container, [
      "bash",
      "-ec",
      `
useradd --create-home workspace-user
RUNTIME_DIR=/run/coder
install -d -m 0711 -o root -g root "$RUNTIME_DIR"
install -m 0600 /dev/null "$RUNTIME_DIR/agent.env"
install -m 0700 /dev/null "$RUNTIME_DIR/init.sh"
systemctl() { echo workspace-user; }
${handoff}
chown_handoff
chown_handoff
runuser -u workspace-user -- bash -ec '
  mkdir -p /run/coder/bin
  touch /run/coder/bin/coder
  test -r /run/coder/agent.env
  test -x /run/coder/init.sh
  test ! -w /run/coder
'
stat -c '%U:%a' "$RUNTIME_DIR"
`,
    ]);
    if (result.exitCode !== 0) console.error(result.stderr);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("root:711");
  } finally {
    await removeContainer(container);
  }
}, 120_000);
