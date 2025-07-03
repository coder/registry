import { describe, expect, it } from "bun:test";
import {
  type TerraformState,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

type TestVariables = Readonly<{
  agent_id: string;
  agent_name: string;
  username?: string;
  password?: string;
  display_name?: string;
  order?: number;
}>;

function findRdpApp(state: TerraformState) {
  for (const resource of state.resources) {
    const isRdpAppResource =
      resource.type === "coder_app" && resource.name === "rdp_desktop";

    if (!isRdpAppResource) {
      continue;
    }

    for (const instance of resource.instances) {
      if (instance.attributes.slug === "rdp-desktop") {
        return instance.attributes;
      }
    }
  }

  return null;
}

function findRdpScript(state: TerraformState) {
  for (const resource of state.resources) {
    const isRdpScriptResource =
      resource.type === "coder_script" && resource.name === "rdp_setup";

    if (!isRdpScriptResource) {
      continue;
    }

    for (const instance of resource.instances) {
      if (instance.attributes.display_name === "Configure RDP") {
        return instance.attributes;
      }
    }
  }

  return null;
}

describe("local-windows-rdp", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "test-agent-id",
    agent_name: "test-agent",
  });

  it("should create RDP app with default values", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "main",
    });

    const app = findRdpApp(state);

    // Verify the app was created
    expect(app).not.toBeNull();
    expect(app?.slug).toBe("rdp-desktop");
    expect(app?.display_name).toBe("RDP Desktop");
    expect(app?.icon).toBe("/icon/desktop.svg");
    expect(app?.external).toBe(true);

    // Verify the URI format
    expect(app?.url).toStartWith("coder://");
    expect(app?.url).toContain("/v0/open/ws/");
    expect(app?.url).toContain("/agent/main/rdp");
    expect(app?.url).toContain("username=Administrator");
    expect(app?.url).toContain("password=coderRDP!");
  });

  it("should create RDP configuration script", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "main",
    });

    const script = findRdpScript(state);

    // Verify the script was created
    expect(script).not.toBeNull();
    expect(script?.display_name).toBe("Configure RDP");
    expect(script?.icon).toBe("/icon/desktop.svg");
    expect(script?.run_on_start).toBe(true);
    expect(script?.run_on_stop).toBe(false);

    // Verify the script contains PowerShell configuration
    expect(script?.script).toContain("Set-AdminPassword");
    expect(script?.script).toContain("Enable-RDP");
    expect(script?.script).toContain("Configure-Firewall");
    expect(script?.script).toContain("Start-RDPService");
  });

  it("should create RDP app with custom values", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "custom-agent-id",
      agent_name: "windows-agent",
      username: "CustomUser",
      password: "CustomPass123!",
      display_name: "Custom RDP",
      order: 5,
    });

    const app = findRdpApp(state);

    // Verify custom values
    expect(app?.display_name).toBe("Custom RDP");
    expect(app?.order).toBe(5);

    // Verify custom credentials in URI
    expect(app?.url).toContain("/agent/windows-agent/rdp");
    expect(app?.url).toContain("username=CustomUser");
    expect(app?.url).toContain("password=CustomPass123!");
  });

  it("should pass custom credentials to PowerShell script", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "main",
      username: "TestAdmin",
      password: "TestPassword123!",
    });

    const script = findRdpScript(state);

    // Verify custom credentials are in the script
    expect(script?.script).toContain('$username = "TestAdmin"');
    expect(script?.script).toContain('$password = "TestPassword123!"');
  });

  it("should handle sensitive password variable", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "main",
      password: "SensitivePass123!",
    });

    const app = findRdpApp(state);

    // Verify password is included in URI even when sensitive
    expect(app?.url).toContain("password=SensitivePass123!");
  });

  it("should use correct default agent name", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "main",
    });

    const app = findRdpApp(state);
    expect(app?.url).toContain("/agent/main/rdp");
  });

  it("should construct proper Coder URI format", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      agent_name: "test-agent",
      username: "TestUser",
      password: "TestPass",
    });

    const app = findRdpApp(state);

    // Verify complete URI structure
    expect(app?.url).toMatch(
      /^coder:\/\/[^\/]+\/v0\/open\/ws\/[^\/]+\/agent\/test-agent\/rdp\?username=TestUser&password=TestPass$/,
    );
  });
});
