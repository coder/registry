import { it, expect, describe } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "~test";

describe("jetbrains-plugins", async () => {
  await runTerraformInit(import.meta.dir);

  await testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    folder: "/home/foo",
  });

  // Test without plugins (should only create base JetBrains apps)
  describe("without plugins", () => {
    it("should create only base JetBrains apps when no plugins specified", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["IU", "PY"]',
        // No plugins specified
      });

      // Should create JetBrains apps through the base module
      const jetbrains_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains"
      );
      expect(jetbrains_apps.length).toBeGreaterThan(0);

      // Should NOT create plugin configuration script
      const plugin_scripts = state.resources.filter(
        (res) => res.type === "coder_script" && res.name === "jetbrains_plugins"
      );
      expect(plugin_scripts.length).toBe(0);
    });
  });

  // Test with plugins (should create base apps + plugin script)
  describe("with plugins", () => {
    it("should create JetBrains apps and plugin configuration script", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["IU", "PY"]',
        plugins: '["org.jetbrains.plugins.github", "com.intellij.ml.llm"]',
      });

      // Should create JetBrains apps through the base module
      const jetbrains_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains"
      );
      expect(jetbrains_apps.length).toBeGreaterThan(0);

      // Should create plugin configuration script
      const plugin_scripts = state.resources.filter(
        (res) => res.type === "coder_script" && res.name === "jetbrains_plugins"
      );
      expect(plugin_scripts.length).toBe(1);

      const script = plugin_scripts[0];
      expect(script.instances[0].attributes.display_name).toBe("Configure JetBrains Plugins");
      expect(script.instances[0].attributes.run_on_start).toBe(true);
      expect(script.instances[0].attributes.start_blocks_login).toBe(false);

      // Check that plugins are included in the script
      const scriptContent = script.instances[0].attributes.script;
      expect(scriptContent).toContain("org.jetbrains.plugins.github");
      expect(scriptContent).toContain("com.intellij.ml.llm");
    });

    it("should work with parameter mode and plugins", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        // default is empty (parameter mode)
        plugins: '["org.jetbrains.plugins.github"]',
      });

      // Should create parameter for IDE selection (through base module)
      const parameters = state.resources.filter(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ides"
      );
      expect(parameters.length).toBe(1);

      // Should create plugin configuration script
      const plugin_scripts = state.resources.filter(
        (res) => res.type === "coder_script" && res.name === "jetbrains_plugins"
      );
      expect(plugin_scripts.length).toBe(1);
    });

    it("should pass through all base module parameters correctly", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        folder: "/workspace",
        default: '["GO"]',
        major_version: "2025.1",
        channel: "eap",
        plugins: '["org.jetbrains.plugins.github"]',
        coder_app_order: 5,
      });

      // Should create GoLand app with correct parameters
      const jetbrains_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains"
      );
      expect(jetbrains_apps.length).toBe(1);

      const app = jetbrains_apps[0];
      expect(app.instances[0].attributes.agent_id).toBe("test-agent");
      expect(app.instances[0].attributes.display_name).toBe("GoLand");
      expect(app.instances[0].attributes.order).toBe(5);
      expect(app.instances[0].attributes.url).toContain("folder=/workspace");
    });

    it("should work with single plugin", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["IU"]',
        plugins: '["Pythonid"]',
      });

      // Should create plugin script with single plugin
      const plugin_scripts = state.resources.filter(
        (res) => res.type === "coder_script" && res.name === "jetbrains_plugins"
      );
      expect(plugin_scripts.length).toBe(1);

      const scriptContent = plugin_scripts[0].instances[0].attributes.script;
      expect(scriptContent).toContain("Pythonid");
      expect(scriptContent).toContain("PLUGINS=(Pythonid)");
    });

    it("should work with empty plugins list", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["IU"]',
        plugins: '[]',
      });

      // Should NOT create plugin script when plugins list is empty
      const plugin_scripts = state.resources.filter(
        (res) => res.type === "coder_script" && res.name === "jetbrains_plugins"
      );
      expect(plugin_scripts.length).toBe(0);

      // Should still create base JetBrains apps
      const jetbrains_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains"
      );
      expect(jetbrains_apps.length).toBe(1);
    });
  });

  // Test base module integration
  describe("base module integration", () => {
    it("should preserve all base module functionality", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["IU", "WS"]',
        major_version: "latest",
        channel: "release",
      });

      // Should create multiple IDE apps
      const jetbrains_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains"
      );
      expect(jetbrains_apps.length).toBe(2);

      // Check app properties
      const app_names = jetbrains_apps.map(
        (app) => app.instances[0].attributes.display_name
      );
      expect(app_names).toContain("IntelliJ IDEA");
      expect(app_names).toContain("WebStorm");

      // Check URLs contain proper JetBrains Gateway links
      jetbrains_apps.forEach((app) => {
        const url = app.instances[0].attributes.url;
        expect(url).toContain("jetbrains://gateway/coder");
        expect(url).toContain("ide_product_code=");
        expect(url).toContain("ide_build_number=");
      });
    });
  });
});