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
const storageConf = "/home/coder/.config/containers/storage.conf";

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

const stub = (tool: string) =>
  `#!/bin/bash\necho "${tool} $*"\n[ "$1" = --version ] && echo "${tool} version 1.0.0"\nexit 0\n`;

let cleanups: (() => Promise<void>)[] = [];
afterEach(async () => {
  const pending = cleanups.reverse();
  cleanups = [];
  for (const cleanup of pending) {
    await cleanup().catch((err) => console.error("cleanup failed:", err));
  }
});

const setup = async (
  vars: Record<string, string> = {},
  tools: string[] = ["podman"],
) => {
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
  for (const tool of tools) {
    await writeExecutable({
      containerId: id,
      filePath: `/usr/local/bin/${tool}`,
      content: stub(tool),
    });
  }
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/install.sh",
    content: installScript(state),
  });
  const run = async () => {
    const result = await execContainer(id, ["bash", "-c", "/tmp/install.sh"]);
    return { ...result, output: result.stdout + result.stderr };
  };
  return { id, run };
};

setDefaultTimeout(60 * 1000);

describe("podman-setup", () => {
  beforeAll(async () => {
    await runTerraformInit(moduleDir);
  });

  test("configures native overlay when podman is present", async () => {
    const { id, run } = await setup();
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("podman info");
    const conf = await readFileContainer(id, storageConf);
    expect(conf).toContain("droopy4096/podman-setup");
    expect(conf).toContain('mount_program = ""');
  });

  test("leaves a user-managed storage.conf alone", async () => {
    const { id, run } = await setup();
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p $(dirname ${storageConf}) && echo '[storage]' > ${storageConf}`,
    ]);
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("Leaving user-managed");
    expect((await readFileContainer(id, storageConf)).trim()).toBe("[storage]");
  });

  test("fails when podman is missing", async () => {
    const { run } = await setup({}, []);
    const result = await run();
    expect(result.exitCode).not.toBe(0);
    expect(result.output).toContain(
      "required tools missing from the image: podman.",
    );
  });

  test("lists every missing required tool in one error", async () => {
    const { id, run } = await setup({
      required_tools: '["buildah", "skopeo"]',
    });
    const result = await run();
    expect(result.exitCode).not.toBe(0);
    expect(result.output).toContain(
      "required tools missing from the image: buildah skopeo.",
    );
    expect(result.output).toContain("apt-get install -y buildah skopeo");
    // Nothing gets configured when the image is incomplete.
    const conf = await execContainer(id, ["test", "-e", storageConf]);
    expect(conf.exitCode).not.toBe(0);
  });

  test("passes when required tools are present and reports them", async () => {
    const { run } = await setup({ required_tools: '["buildah", "skopeo"]' }, [
      "podman",
      "buildah",
      "skopeo",
    ]);
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("buildah version 1.0.0");
    expect(result.output).toContain("skopeo version 1.0.0");
  });

  test("buildah and skopeo are optional by default", async () => {
    const { run } = await setup();
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).not.toContain("missing");
  });

  test("links docker to podman when the image has no docker", async () => {
    const { id, run } = await setup();
    await execContainer(
      id,
      ["rm", "-f", "/usr/bin/docker"],
      ["--user", "root"],
    );
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("Linked /usr/local/bin/docker");
    const link = await execContainer(id, ["readlink", "/usr/local/bin/docker"]);
    expect(link.stdout.trim()).toBe("/usr/local/bin/podman");
    const docker = await execContainer(id, ["bash", "-c", "docker ps"]);
    expect(docker.stdout).toContain("podman ps");
  });

  test("falls back to ~/.local/bin without sudo", async () => {
    const { id, run } = await setup();
    await execContainer(
      id,
      ["rm", "-f", "/usr/bin/docker"],
      ["--user", "root"],
    );
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/sudo",
      content: "#!/bin/bash\nexit 1\n",
    });
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("is not on PATH");
    const link = await execContainer(id, [
      "readlink",
      "/home/coder/.local/bin/docker",
    ]);
    expect(link.stdout.trim()).toBe("/usr/local/bin/podman");
  });

  test("keeps an existing docker CLI", async () => {
    const { id, run } = await setup();
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain(
      "Keeping the existing docker CLI at /usr/bin/docker",
    );
    const link = await execContainer(id, [
      "test",
      "-e",
      "/usr/local/bin/docker",
    ]);
    expect(link.exitCode).not.toBe(0);
  });

  test("leaves docker alone when docker_shim = false", async () => {
    const { id, run } = await setup({ docker_shim: "false" });
    await execContainer(
      id,
      ["rm", "-f", "/usr/bin/docker"],
      ["--user", "root"],
    );
    const result = await run();
    expect(result.exitCode).toBe(0);
    expect(result.output).not.toContain("docker");
    const link = await execContainer(id, ["bash", "-c", "command -v docker"]);
    expect(link.exitCode).not.toBe(0);
  });
});
