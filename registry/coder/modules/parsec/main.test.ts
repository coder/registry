import { describe, expect, it } from "bun:test";
import {
  type TerraformState,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

type TestVariables = Readonly<{
  agent_id: string;
  display_name?: string;
  slug?: string;
  icon?: string;
  order?: number;
  group?: string;
  parsec_team_id?: string;
  parsec_team_key?: string;
  host_name?: string;
  auto_start?: boolean;
}>;

function findParsecScript(state: TerraformState): string | null {
  for (const resource of state.resources) {
    const isParsecScriptResource =
      resource.type === "coder_script" && resource.name === "parsec";

    if (!isParsecScriptResource) {
      continue;
    }

    for (const instance of resource.instances) {
      if (
        instance.attributes.display_name === "Parsec" &&
        typeof instance.attributes.script === "string"
      ) {
        return instance.attributes.script;
      }
    }
  }

  return null;
}

function findParsecApp(
  state: TerraformState,
  appName: string = "parsec",
): Record<string, unknown> | null {
  for (const resource of state.resources) {
    if (resource.type === "coder_app" && resource.name === appName) {
      for (const instance of resource.instances) {
        return instance.attributes;
      }
    }
  }
  return null;
}

describe("Parsec Module", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "test-agent-id",
  });

  it("Has the PowerShell script download and install Parsec", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
    });

    const script = findParsecScript(state);
    expect(script).toBeString();
    expect(script).toContain(
      "https://builds.parsec.app/package/parsec-windows.msi",
    );
    expect(script).toContain("msiexec.exe");
    expect(script).toContain("Parsec installed successfully");
  });

  it("Creates external Parsec app link", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
    });

    const app = findParsecApp(state, "parsec");
    expect(app).not.toBeNull();
    expect(app?.display_name).toBe("Parsec");
    expect(app?.url).toBe("https://web.parsec.app/");
    expect(app?.external).toBe(true);
  });

  it("Creates Parsec docs app link", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
    });

    const app = findParsecApp(state, "parsec-docs");
    expect(app).not.toBeNull();
    expect(app?.display_name).toBe("Parsec Docs");
    expect(app?.url).toBe("https://support.parsec.app/hc/en-us");
    expect(app?.external).toBe(true);
  });

  it("Configures custom hostname when provided", async () => {
    const customHostname = "my-gaming-pc";
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      host_name: customHostname,
    });

    const script = findParsecScript(state);
    expect(script).toBeString();
    expect(script).toContain(`$HostName = "${customHostname}"`);
    expect(script).toContain(`host_name = ${customHostname}`);
  });

  it("Configures Parsec Teams credentials when provided", async () => {
    const teamId = "team-12345";
    const teamKey = "secret-key-abc";
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      parsec_team_id: teamId,
      parsec_team_key: teamKey,
    });

    const script = findParsecScript(state);
    expect(script).toBeString();
    expect(script).toContain(`$ParsecTeamId = "${teamId}"`);
    expect(script).toContain(`$ParsecTeamKey = "${teamKey}"`);
    expect(script).toContain("Configuring Parsec Teams authentication");
  });

  it("Supports custom display name and slug", async () => {
    const customDisplayName = "Cloud Gaming";
    const customSlug = "cloud-gaming";
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      display_name: customDisplayName,
      slug: customSlug,
    });

    const app = findParsecApp(state, "parsec");
    expect(app).not.toBeNull();
    expect(app?.display_name).toBe(customDisplayName);
    expect(app?.slug).toBe(customSlug);
  });

  it("Configures auto_start behavior", async () => {
    // Test with auto_start enabled (default)
    const stateAutoStart = await runTerraformApply<TestVariables>(
      import.meta.dir,
      {
        agent_id: "test-agent-id",
        auto_start: true,
      },
    );

    const scriptAutoStart = findParsecScript(stateAutoStart);
    expect(scriptAutoStart).toContain(
      '$AutoStart = [System.Convert]::ToBoolean("true")',
    );
    expect(scriptAutoStart).toContain("Starting Parsec...");

    // Test with auto_start disabled
    const stateNoAutoStart = await runTerraformApply<TestVariables>(
      import.meta.dir,
      {
        agent_id: "test-agent-id",
        auto_start: false,
      },
    );

    const scriptNoAutoStart = findParsecScript(stateNoAutoStart);
    expect(scriptNoAutoStart).toContain(
      '$AutoStart = [System.Convert]::ToBoolean("false")',
    );
  });
});
