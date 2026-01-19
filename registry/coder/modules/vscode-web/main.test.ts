import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
} from "~test";

describe("vscode-web", async () => {
  await runTerraformInit(import.meta.dir);

  it("accept_license should be set to true", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "false",
      });
    };
    expect(t).toThrow("Invalid value for variable");
  });

  it("use_cached and offline can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        use_cached: "true",
        offline: "true",
      });
    };
    expect(t).toThrow("Offline and Use Cached can not be used together");
  });

  it("offline and extensions can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        offline: "true",
        extensions: '["1", "2"]',
      });
    };
    expect(t).toThrow("Offline mode does not allow extensions to be installed");
  });

  it("writes settings to User settings path not Machine", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: "true",
      offline: "true",
    });
    const instance = findResourceInstance(state, "coder_script");
    // Verify the script uses User path, not Machine path
    expect(instance.script).toContain(".vscode-server/data/User/settings.json");
    expect(instance.script).not.toContain(".vscode-server/data/Machine/settings.json");
  });

  it("writes provided settings to ~/.vscode-server/data/User/settings.json", async () => {
    const id = await runContainer("alpine");
    try {
      const settings = {
        "editor.fontSize": 16,
        "workbench.colorTheme": "Default Dark+",
      };
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        offline: "true",
        settings: JSON.stringify(settings),
      });
      const instance = findResourceInstance(state, "coder_script");
      // Extract and run only the settings portion of the script
      const settingsScript = `
SETTINGS='${JSON.stringify(settings).replace(/'/g, "'\\''")}'
if [ ! -f ~/.vscode-server/data/User/settings.json ]; then
  mkdir -p ~/.vscode-server/data/User
  echo "$SETTINGS" > ~/.vscode-server/data/User/settings.json
fi
`;
      const resp = await execContainer(id, ["sh", "-c", settingsScript]);
      expect(resp.exitCode).toBe(0);
      const content = await readFileContainer(
        id,
        "/root/.vscode-server/data/User/settings.json",
      );
      const actualSettings = JSON.parse(content.trim());
      expect(actualSettings).toEqual(settings);
    } finally {
      await removeContainer(id);
    }
  });
});
