import { describe, expect, it } from "bun:test";
import {
  type TerraformState,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

type TestVariables = Readonly<{
  agent_id: string;
  agent_name?: string;
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

describe("local-windows-rdp", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "test-agent-id",
  });

  it("should create RDP app with default values", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
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

  it("should handle sensitive password variable", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      password: "SensitivePass123!",
    });

    const app = findRdpApp(state);

    // Verify password is included in URI even when sensitive
    expect(app?.url).toContain("password=SensitivePass123!");
  });

  it("should use correct default agent name", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
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
