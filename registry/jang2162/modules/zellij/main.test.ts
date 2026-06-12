import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("zellij", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default mode should be terminal", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const terminalApp = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "zellij_terminal",
    );
    const webApp = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "zellij_web",
    );
    expect(terminalApp).toBeDefined();
    expect(terminalApp!.instances.length).toBe(1);
    expect(terminalApp!.instances[0].attributes.command).toBe(
      "zellij attach --create default",
    );
    expect(webApp).toBeUndefined();
  });

  it("web mode should create web app", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      mode: "web",
    });
    const webApp = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "zellij_web",
    );
    const terminalApp = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "zellij_terminal",
    );
    expect(webApp).toBeDefined();
    expect(webApp!.instances.length).toBe(1);
    expect(webApp!.instances[0].attributes.subdomain).toBe(true);
    expect(webApp!.instances[0].attributes.url).toBe("http://localhost:8082");
    expect(terminalApp).toBeUndefined();
  });

  it("web mode should use custom port", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      mode: "web",
      web_port: 9090,
    });
    const webApp = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "zellij_web",
    );
    expect(webApp).toBeDefined();
    expect(webApp!.instances[0].attributes.url).toBe("http://localhost:9090");
  });
});
