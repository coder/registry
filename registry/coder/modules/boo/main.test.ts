import {
  test,
  afterEach,
  describe,
  setDefaultTimeout,
  beforeAll,
  expect,
} from "bun:test";
import {
  execContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  TerraformState,
} from "~test";
import { writeExecutable } from "../agentapi/test-util";

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
}

const SCRIPT_SUFFIXES = [
  "Pre-Install Script",
  "Install Script",
  "Post-Install Script",
] as const;

const collectScripts = (state: TerraformState): ModuleScripts => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      const displayName = attrs.display_name as string | undefined;
      const script = attrs.script as string | undefined;
      if (displayName && script) {
        byDisplayName[displayName] = script;
      }
    }
  }
  const scripts: Partial<ModuleScripts> = {};
  for (const suffix of SCRIPT_SUFFIXES) {
    const key = `Boo: ${suffix}`;
    if (!(key in byDisplayName)) continue;
    switch (suffix) {
      case "Pre-Install Script":
        scripts.pre_install = byDisplayName[key];
        break;
      case "Install Script":
        scripts.install = byDisplayName[key];
        break;
      case "Post-Install Script":
        scripts.post_install = byDisplayName[key];
        break;
    }
  }
  if (!scripts.install) {
    throw new Error("install script not found in terraform state");
  }
  return scripts as ModuleScripts;
};

const findAppBySlug = (
  state: TerraformState,
  slug: string,
): Record<string, unknown> => {
  for (const resource of state.resources) {
    if (resource.type !== "coder_app") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      if (attrs.slug === slug) return attrs;
    }
  }
  throw new Error(`coder_app with slug '${slug}' not found in terraform state`);
};

const countApps = (state: TerraformState): number => {
  let count = 0;
  for (const resource of state.resources) {
    if (resource.type === "coder_app") {
      count += resource.instances.length;
    }
  }
  return count;
};

let cleanupFunctions: (() => Promise<void>)[] = [];
const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};
afterEach(async () => {
  const fns = cleanupFunctions.slice().reverse();
  cleanupFunctions = [];
  for (const fn of fns) {
    try {
      await fn();
    } catch (error) {
      console.error("Error during cleanup:", error);
    }
  }
});

const defaultSession =
  '[{"session_name":"main","display_name":"Main","slug":"boo-main","command":"bash"}]';

const setup = async (moduleVariables?: Record<string, string>) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    sessions: defaultSession,
    install_boo: "false",
    ...moduleVariables,
  });
  const scripts = collectScripts(state);
  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (process.env["DEBUG"] === "true" || process.env["DEBUG"] === "1") return;
    await removeContainer(id);
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  return { id, state, scripts };
};

const runScripts = async (id: string, scripts: ModuleScripts) => {
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const target = `/tmp/boo-${name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: target,
      content: script,
    });
    const resp = await execContainer(id, ["bash", "-c", target]);
    if (resp.exitCode !== 0) {
      throw new Error(
        `${name} script exited ${resp.exitCode}:\n${resp.stdout}\n${resp.stderr}`,
      );
    }
  }
};

setDefaultTimeout(60 * 1000);

describe("boo", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("defaults", async () => {
    const { state } = await setup();
    const app = findAppBySlug(state, "boo-main");
    expect(app.display_name).toBe("Main");
    expect(app.icon).toBe("/icon/coder.svg");
    expect(app.order).toBeNull();
    expect(app.group).toBeNull();
  });

  test("multiple-sessions-create-multiple-apps", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions:
        '[{"session_name":"alpha","display_name":"Alpha","slug":"alpha","command":"bash"},{"session_name":"beta","display_name":"Beta","slug":"beta","command":"vim"}]',
    });
    expect(countApps(state)).toBe(2);
    const alpha = findAppBySlug(state, "alpha");
    const beta = findAppBySlug(state, "beta");
    expect(alpha.display_name).toBe("Alpha");
    expect(beta.display_name).toBe("Beta");
  });

  test("per-session-slug-and-display-name", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions:
        '[{"session_name":"main","display_name":"Terminal: main","slug":"term-main","command":"bash"}]',
    });
    const app = findAppBySlug(state, "term-main");
    expect(app.slug).toBe("term-main");
    expect(app.display_name).toBe("Terminal: main");
  });

  test("session-name-used-in-boo-command", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions:
        '[{"session_name":"my-session","display_name":"My Session","slug":"my-boo","command":"bash"}]',
    });
    const app = findAppBySlug(state, "my-boo");
    expect(app.command as string).toContain("'my-session'");
    expect(app.command as string).not.toContain("'my-boo'");
  });

  test("derived-slug-from-session-name", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions: '[{"session_name":"my.dev_server","command":"bash"}]',
    });
    const app = findAppBySlug(state, "my-dev-server");
    expect(app.slug).toBe("my-dev-server");
  });

  test("derived-display-name-from-session-name", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions: '[{"session_name":"my-session","command":"bash"}]',
    });
    const app = findAppBySlug(state, "my-session");
    expect(app.display_name).toBe("my-session");
  });

  test("order-and-group", async () => {
    const { state } = await setup({ order: "5", group: "ai-tools" });
    const app = findAppBySlug(state, "boo-main");
    expect(app.order).toBe(5);
    expect(app.group).toBe("ai-tools");
  });

  test("install-skipped-when-install-boo-false", async () => {
    const { id, scripts } = await setup({ install_boo: "false" });
    await runScripts(id, scripts);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "command -v boo && echo FOUND || echo ABSENT",
    ]);
    expect(resp.stdout.trim()).toBe("ABSENT");
  });

  test("install-skipped-when-boo-already-installed", async () => {
    const { id, scripts } = await setup({ install_boo: "true" });
    await execContainer(id, ["mkdir", "-p", "/home/coder/.local/bin"]);
    await writeExecutable({
      containerId: id,
      filePath: "/home/coder/.local/bin/boo",
      content:
        '#!/bin/bash\nif [ "$1" = "-V" ]; then echo "0.6.4"; fi\nexit 0\n',
    });
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `export PATH="$HOME/.local/bin:$PATH" && /tmp/boo-install.sh 2>&1 || true`,
    ]);
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/boo-install.sh",
      content: scripts.install,
    });
    const result = await execContainer(id, [
      "bash",
      "-c",
      'export PATH="$HOME/.local/bin:$PATH" && /tmp/boo-install.sh',
    ]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("already installed");
  });

  test("pre-post-install-scripts", async () => {
    const { scripts } = await setup({
      pre_install_script: "#!/bin/bash\necho 'boo-pre-install'",
      post_install_script: "#!/bin/bash\necho 'boo-post-install'",
    });
    expect(scripts.pre_install).toBeDefined();
    expect(scripts.post_install).toBeDefined();
  });

  test("custom-install-script-url", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      sessions: defaultSession,
      install_boo: "true",
      install_script_url: "https://mirror.example.com/boo/install.sh",
    });
    const scripts = collectScripts(state);
    const match = scripts.install.match(
      /echo -n '([A-Za-z0-9+/=]+)' \| base64 -d/,
    );
    expect(match).not.toBeNull();
    const decoded = Buffer.from(match![1], "base64").toString("utf8");
    expect(decoded).toContain("https://mirror.example.com/boo/install.sh");
  });

  test("install-only-no-sessions", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_boo: "false",
    });
    expect(countApps(state)).toBe(0);
  });
});
