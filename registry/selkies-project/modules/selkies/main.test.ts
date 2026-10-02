import { afterEach, describe, expect, it, setDefaultTimeout } from "bun:test";
import path from "node:path";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type TerraformState,
  testRequiredVariables,
  writeCoder,
  writeFileContainer,
} from "~test";

setDefaultTimeout(120_000);

const IMAGE = "node:22-bookworm-slim";

type Variables = Readonly<{
  agent_id: string;
  desktop_environment?: string;
  port?: number;
  install_selkies?: boolean;
}>;

interface Scripts {
  install: string;
  start: string;
}

const scriptsOf = (state: TerraformState): Scripts => {
  const scripts: Partial<Scripts> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") {
      continue;
    }
    for (const instance of resource.instances) {
      const { display_name: name, script } = instance.attributes as Record<
        string,
        unknown
      >;
      if (typeof script !== "string") {
        continue;
      }
      if (name === "Selkies: Install Script") {
        scripts.install = script;
      } else if (name === "Selkies: Start Script") {
        scripts.start = script;
      }
    }
  }
  if (!scripts.install || !scripts.start) {
    throw new Error("the module must create an install and a start script");
  }
  return scripts as Scripts;
};

let containers: string[] = [];

afterEach(async () => {
  for (const id of containers) {
    await removeContainer(id);
  }
  containers = [];
});

// A workspace with the coder CLI stubbed and, as an image carrying Selkies
// would have them, a launcher and an Xvfb on PATH
const workspace = async (launcher?: string): Promise<string> => {
  const id = await runContainer(IMAGE);
  containers.push(id);
  await writeCoder(id, "#!/bin/sh\nexit 0\n");
  if (launcher !== undefined) {
    await writeFileContainer(id, "/usr/local/bin/selkies-session", launcher, {
      user: "root",
    });
    await writeFileContainer(id, "/usr/local/bin/Xvfb", "#!/bin/sh\n", {
      user: "root",
    });
    await execContainer(
      id,
      ["chmod", "755", "/usr/local/bin/selkies-session", "/usr/local/bin/Xvfb"],
      ["--user", "root"],
    );
  }
  return id;
};

const mockLauncher = () =>
  Bun.file(
    path.join(import.meta.dir, "testdata", "selkies-session-mock.sh"),
  ).text();

const run = (id: string, script: string) =>
  execContainer(id, ["bash", "-c", script]);

describe("selkies", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables<Variables>(import.meta.dir, { agent_id: "foo" });

  it("installs nothing where the image has Selkies, and starts it behind the app's port", async () => {
    const scripts = scriptsOf(
      await runTerraformApply<Variables>(import.meta.dir, {
        agent_id: "foo",
        desktop_environment: "xfce",
      }),
    );
    const id = await workspace(await mockLauncher());

    const install = await run(id, scripts.install);
    expect(install.exitCode).toBe(0);
    expect(install.stdout).toContain(
      "Selkies and its display server are installed",
    );

    const start = await run(id, scripts.start);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain("Selkies is ready on port 8080");
    const args = await readFileContainer(id, "/tmp/selkies-session.args");
    expect(args.trim().split("\n")).toEqual([
      "--port=8080",
      "--enable-basic-auth=false",
      "--enable-https=false",
      "--session=xfce",
    ]);

    const again = await run(id, scripts.start);
    expect(again.exitCode).toBe(0);
    expect(again.stdout).toContain("Selkies already answers on port 8080");
  });

  it("installs nothing when install_selkies is false, and says what is missing", async () => {
    const scripts = scriptsOf(
      await runTerraformApply<Variables>(import.meta.dir, {
        agent_id: "foo",
        install_selkies: false,
      }),
    );
    const id = await workspace();

    const install = await run(id, scripts.install);
    expect(install.exitCode).not.toBe(0);
    expect(install.stdout).toContain(
      "The workspace lacks selkies-session Xvfb and install_selkies is false",
    );
  });

  it("reports a Selkies that exits before it answers", async () => {
    const scripts = scriptsOf(
      await runTerraformApply<Variables>(import.meta.dir, {
        agent_id: "foo",
        port: 8081,
      }),
    );
    const id = await workspace(
      "#!/bin/sh\necho 'Xvfb did not come up' >&2\nexit 1\n",
    );

    // The install script runs first, as Coder orders them, and lays out the module's directory
    expect((await run(id, scripts.install)).exitCode).toBe(0);
    const start = await run(id, scripts.start);
    expect(start.exitCode).not.toBe(0);
    expect(start.stdout).toContain("Selkies exited before it answered");
    expect(start.stdout).toContain("Xvfb did not come up");
  });
});
