import {
  afterEach,
  beforeAll,
  describe,
  expect,
  setDefaultTimeout,
  test,
} from "bun:test";
import path from "path";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type TerraformState,
} from "~test";
import { writeExecutable } from "../../../coder/modules/agentapi/test-util";

const moduleDir = path.resolve(import.meta.dir);

const installScript = (state: TerraformState): string => {
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      if (attrs.display_name === "Podman: Install Script") {
        return attrs.script as string;
      }
    }
  }
  throw new Error("install coder_script not found");
};

// Record package manager calls (and who made them) instead of installing.
const fakeAptGet = `#!/bin/bash
echo "uid=$(id -u) $*" >> /tmp/pm-calls
if [ "$1" = install ]; then
  for arg in "$@"; do
    case "$arg" in
      buildah | skopeo) printf '#!/bin/bash\\necho "%s version 1.0.0"\\n' "$arg" > "/usr/local/bin/$arg"; chmod +x "/usr/local/bin/$arg" ;;
    esac
  done
fi
`;

let cleanups: (() => Promise<void>)[] = [];
afterEach(async () => {
  const pending = cleanups.reverse();
  cleanups = [];
  for (const cleanup of pending) {
    await cleanup().catch((err) => console.error("cleanup failed:", err));
  }
});

const setup = async (vars: Record<string, string> = {}) => {
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    socket: "false",
    ...vars,
  });
  const id = await runContainer("codercom/enterprise-node:latest");
  cleanups.push(() => removeContainer(id));
  // coder-utils calls `coder exp sync`; a no-op stub is enough here.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/podman",
    content: '#!/bin/bash\necho "podman $*"\n',
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/apt-get",
    content: fakeAptGet,
  });
  const script = installScript(state);
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/install.sh",
    content: script,
  });
  return { id };
};

const runInstall = (id: string, user = "root") =>
  execContainer(
    id,
    ["bash", "-c", "cd ~ && /tmp/install.sh"],
    ["--user", user],
  );

const pmCalls = async (id: string) =>
  (
    await execContainer(id, ["bash", "-c", "cat /tmp/pm-calls 2>/dev/null"])
  ).stdout.trim();

setDefaultTimeout(60 * 1000);

describe("podman-rootless", () => {
  beforeAll(async () => {
    await runTerraformInit(moduleDir);
  });

  test("installs missing buildah and skopeo as root", async () => {
    const { id } = await setup();
    const result = await runInstall(id);
    expect(result.exitCode).toBe(0);
    expect(await pmCalls(id)).toContain(
      "uid=0 install -y -qq --no-install-recommends buildah skopeo",
    );
    expect(result.stdout).toContain("buildah version 1.0.0");
    expect(result.stdout).toContain("skopeo version 1.0.0");
  });

  test("installs through passwordless sudo", async () => {
    const { id } = await setup({ extra_tools: '["skopeo"]' });
    await execContainer(
      id,
      [
        "bash",
        "-c",
        "echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/test-coder",
      ],
      ["--user", "root"],
    );
    const result = await runInstall(id, "coder");
    expect(result.exitCode).toBe(0);
    const calls = await pmCalls(id);
    expect(calls).toContain("uid=0 install");
    expect(calls).toContain("skopeo");
    expect(calls).not.toContain("buildah");
  });

  test("warns without root or sudo and keeps going", async () => {
    const { id } = await setup();
    await execContainer(
      id,
      [
        "bash",
        "-c",
        "rm -f /etc/sudoers.d/* && sed -i '/coder/d' /etc/sudoers",
      ],
      ["--user", "root"],
    );
    const result = await runInstall(id, "coder");
    expect(result.exitCode).toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "WARNING: buildah skopeo not installed, and installing needs root or passwordless sudo",
    );
    expect(await pmCalls(id)).toBe("");
    expect(
      await readFileContainer(
        id,
        "/home/coder/.config/containers/storage.conf",
      ),
    ).toContain('mount_program = ""');
  });

  test("leaves installed tools alone", async () => {
    const { id } = await setup();
    for (const tool of ["buildah", "skopeo"]) {
      await writeExecutable({
        containerId: id,
        filePath: `/usr/local/bin/${tool}`,
        content: `#!/bin/bash\necho "${tool} version 9.9.9"\n`,
      });
    }
    const result = await runInstall(id);
    expect(result.exitCode).toBe(0);
    expect(await pmCalls(id)).toBe("");
    expect(result.stdout).toContain("buildah version 9.9.9");
  });

  test("extra_tools = [] installs nothing", async () => {
    const { id } = await setup({ extra_tools: "[]" });
    const result = await runInstall(id);
    expect(result.exitCode).toBe(0);
    expect(await pmCalls(id)).toBe("");
  });

  test("a failed package install doesn't stop Podman setup", async () => {
    const { id } = await setup();
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/apt-get",
      content: "#!/bin/bash\nexit 100\n",
    });
    const result = await runInstall(id);
    expect(result.exitCode).toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "WARNING: installing buildah skopeo failed",
    );
    expect(result.stdout).toContain("podman info");
  });

  test("fails when podman is missing", async () => {
    const { id } = await setup();
    await execContainer(id, ["rm", "/usr/bin/podman"], ["--user", "root"]);
    const result = await runInstall(id);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain("podman not found");
  });
});
