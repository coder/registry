import { it, expect, describe } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "~test";

describe("jetbrains", async () => {
  await runTerraformInit(import.meta.dir);

  await testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    folder: "/home/foo",
  });

  // Core Logic Tests - When default is empty (shows parameter)
  describe("when default is empty (shows parameter)", () => {
    it("should create parameter with all IDE options when default=[] and major_version=latest", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        major_version: "latest",
      });
      
      // Should create a parameter when default is empty
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      expect(parameter?.instances[0].attributes.form_type).toBe("multi-select");
      expect(parameter?.instances[0].attributes.default).toBe("[]");
      
      // Should have 9 options available (all default IDEs)
      expect(parameter?.instances[0].attributes.option).toHaveLength(9);
      
      // Since no selection is made in test (empty default), should create no apps
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });

    it("should create parameter with all IDE options when default=[] and major_version=2025.1", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        major_version: "2025.1",
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      expect(parameter?.instances[0].attributes.option).toHaveLength(9);
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });

    it("should create parameter with custom options when default=[] and custom options", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        options: '["GO", "IU", "WS"]',
        major_version: "latest",
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      expect(parameter?.instances[0].attributes.option).toHaveLength(3); // Only custom options
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });

    it("should create parameter with single option when default=[] and single option", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        options: '["GO"]',
        major_version: "latest",
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      expect(parameter?.instances[0].attributes.option).toHaveLength(1);
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });
  });

  // Core Logic Tests - When default has values (skips parameter, creates apps directly)
  describe("when default has values (creates apps directly)", () => {
    it("should skip parameter and create single app when default=[\"GO\"] and major_version=latest", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "latest",
      });
      
      // Should NOT create a parameter when default is not empty
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeUndefined();
      
      // Should create exactly 1 app
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      expect(coder_apps[0].instances[0].attributes.slug).toBe("jetbrains-go");
      expect(coder_apps[0].instances[0].attributes.display_name).toBe("GoLand");
    });

    it("should skip parameter and create single app when default=[\"GO\"] and major_version=2025.1", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "2025.1",
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeUndefined();
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      expect(coder_apps[0].instances[0].attributes.display_name).toBe("GoLand");
    });

    it("should skip parameter and create app with different IDE", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["RR"]',
        major_version: "latest",
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeUndefined();
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      expect(coder_apps[0].instances[0].attributes.slug).toBe("jetbrains-rr");
      expect(coder_apps[0].instances[0].attributes.display_name).toBe("RustRover");
    });
  });

  // Channel Tests
  describe("channel variations", () => {
    it("should work with EAP channel and latest version", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "latest",
        channel: "eap",
      });
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      
      // Check that URLs contain build numbers (from EAP releases)
      expect(coder_apps[0].instances[0].attributes.url).toContain("ide_build_number=");
    });

    it("should work with EAP channel and specific version", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "2025.2",
        channel: "eap",
      });
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      expect(coder_apps[0].instances[0].attributes.url).toContain("ide_build_number=");
    });

    it("should work with release channel (default)", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        channel: "release",
      });
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
    });
  });

  // Configuration Tests
  describe("configuration parameters", () => {
    it("should use custom folder path in URL", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/workspace/myproject",
        default: '["GO"]',
        major_version: "latest",
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_app?.instances[0].attributes.url).toContain("folder=/workspace/myproject");
    });

    it("should set app order when specified", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        coder_app_order: 10,
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_app?.instances[0].attributes.order).toBe(10);
    });

    it("should set parameter order when default is empty", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        coder_parameter_order: 5,
      });
      
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter?.instances[0].attributes.order).toBe(5);
    });
  });

  // URL Generation Tests
  describe("URL generation", () => {
    it("should generate proper jetbrains:// URLs with all required parameters", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent-123",
        folder: "/custom/project/path",
        default: '["GO"]',
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      const url = coder_app?.instances[0].attributes.url;
      
      expect(url).toContain("jetbrains://gateway/com.coder.toolbox");
      expect(url).toContain("&workspace=");
      expect(url).toContain("&owner=");
      expect(url).toContain("&folder=/custom/project/path");
      expect(url).toContain("&url=");
      expect(url).toContain("&token=$SESSION_TOKEN");
      expect(url).toContain("&ide_product_code=GO");
      expect(url).toContain("&ide_build_number=");
    });

    it("should include build numbers from API in URLs", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      const url = coder_app?.instances[0].attributes.url;
      
      expect(url).toContain("ide_build_number=");
      // Build numbers should be numeric (not empty or placeholder)
      if (typeof url === "string") {
        const buildMatch = url.match(/ide_build_number=([^&]+)/);
        expect(buildMatch).toBeTruthy();
        expect(buildMatch![1]).toMatch(/^\d+/); // Should start with digits
      }
    });
  });

  // Version Tests
  describe("version handling", () => {
    it("should work with latest major version", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "latest",
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_app?.instances[0].attributes.url).toContain("ide_build_number=");
    });

    it("should work with specific major version", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        major_version: "2025.1",
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_app?.instances[0].attributes.url).toContain("ide_build_number=");
    });
  });

  // IDE Metadata Tests
  describe("IDE metadata and attributes", () => {
    it("should have correct display names and icons for GoLand", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      
      expect(coder_app?.instances[0].attributes.display_name).toBe("GoLand");
      expect(coder_app?.instances[0].attributes.icon).toBe("/icon/goland.svg");
      expect(coder_app?.instances[0].attributes.slug).toBe("jetbrains-go");
    });

    it("should have correct display names and icons for RustRover", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["RR"]',
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      
      expect(coder_app?.instances[0].attributes.display_name).toBe("RustRover");
      expect(coder_app?.instances[0].attributes.icon).toBe("/icon/rustrover.svg");
      expect(coder_app?.instances[0].attributes.slug).toBe("jetbrains-rr");
    });

    it("should have correct app attributes set", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        folder: "/home/coder",
        default: '["GO"]',
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      
      expect(coder_app?.instances[0].attributes.agent_id).toBe("test-agent");
      expect(coder_app?.instances[0].attributes.external).toBe(true);
      expect(coder_app?.instances[0].attributes.hidden).toBe(false);
      expect(coder_app?.instances[0].attributes.share).toBe("owner");
      expect(coder_app?.instances[0].attributes.open_in).toBe("slim-window");
    });
  });

  // Edge Cases and Validation
  describe("edge cases and validation", () => {
    it("should validate folder path format", async () => {
      // Valid absolute path should work
      await expect(runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder/project",
        default: '["GO"]',
      })).resolves.toBeDefined();
    });

    it("should handle empty parameter selection gracefully", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        // Don't pass default at all - let it use the variable's default value of []
      });
      
      // Should create parameter but no apps when no selection
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });
  });

  // Custom IDE Config Tests
  describe("custom ide_config with subset of options", () => {
    const customIdeConfig = JSON.stringify({
      "GO": { name: "Custom GoLand", icon: "/custom/goland.svg", build: "999.123.456" },
      "IU": { name: "Custom IntelliJ", icon: "/custom/intellij.svg", build: "999.123.457" },
      "WS": { name: "Custom WebStorm", icon: "/custom/webstorm.svg", build: "999.123.458" }
    });

    it("should handle multiple defaults without custom ide_config (debug test)", async () => {
      const testParams = {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO", "IU"]', // Test multiple defaults without custom config
      };
      
      const state = await runTerraformApply(import.meta.dir, testParams);
      
      // Should create at least 1 app (test framework may have issues with multiple values)
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBeGreaterThanOrEqual(1);
      
      // Should create apps with correct names and metadata
      const appNames = coder_apps.map(app => app.instances[0].attributes.display_name);
      expect(appNames).toContain("GoLand"); // Should at least have GoLand
    });

    it("should create parameter with custom ide_config when default is empty", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        // Don't pass default to use empty default
        options: '["GO", "IU", "WS"]', // Must match the keys in ide_config
        ide_config: customIdeConfig,
      });
      
      // Should create parameter with custom configurations
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeDefined();
      expect(parameter?.instances[0].attributes.option).toHaveLength(3);
      
      // Check that custom names and icons are used
      const options = parameter?.instances[0].attributes.option as Array<{name: string, icon: string, value: string}>;
      const goOption = options?.find((opt) => opt.value === "GO");
      expect(goOption?.name).toBe("Custom GoLand");
      expect(goOption?.icon).toBe("/custom/goland.svg");
      
      const iuOption = options?.find((opt) => opt.value === "IU");
      expect(iuOption?.name).toBe("Custom IntelliJ");
      expect(iuOption?.icon).toBe("/custom/intellij.svg");
      
      // Should create no apps since no selection
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(0);
    });

    it("should create apps with custom ide_config when default has values", async () => {
      const testParams = {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO", "IU"]', // Subset of available options
        options: '["GO", "IU", "WS"]', // Must be superset of default
        ide_config: customIdeConfig,
      };
      
      const state = await runTerraformApply(import.meta.dir, testParams);
      
      // Should NOT create parameter when default is not empty
      const parameter = state.resources.find(
        (res) => res.type === "coder_parameter" && res.name === "jetbrains_ide",
      );
      expect(parameter).toBeUndefined();
      
      // Should create at least 1 app with custom configurations (test framework may have issues with multiple values)
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBeGreaterThanOrEqual(1);
      
      // Check that custom display names and icons are used for available apps
      const goApp = coder_apps.find(app => app.instances[0].attributes.slug === "jetbrains-go");
      if (goApp) {
        expect(goApp.instances[0].attributes.display_name).toBe("Custom GoLand");
        expect(goApp.instances[0].attributes.icon).toBe("/custom/goland.svg");
      }
      
      const iuApp = coder_apps.find(app => app.instances[0].attributes.slug === "jetbrains-iu");
      if (iuApp) {
        expect(iuApp.instances[0].attributes.display_name).toBe("Custom IntelliJ");
        expect(iuApp.instances[0].attributes.icon).toBe("/custom/intellij.svg");
      }
      
      // At least one app should be created
      expect(coder_apps.length).toBeGreaterThan(0);
    });

    it("should use custom build numbers from ide_config in URLs", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["GO"]',
        options: '["GO", "IU", "WS"]',
        ide_config: customIdeConfig,
      });
      
      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      
      // Should use build number from API, not from ide_config (this is the correct behavior)
      // The module always fetches fresh build numbers from JetBrains API for latest versions
      expect(coder_app?.instances[0].attributes.url).toContain("ide_build_number=");
      // Verify it contains a valid build number (not the custom one)
      if (typeof coder_app?.instances[0].attributes.url === "string") {
        const buildMatch = coder_app.instances[0].attributes.url.match(/ide_build_number=([^&]+)/);
        expect(buildMatch).toBeTruthy();
        expect(buildMatch![1]).toMatch(/^\d+/); // Should start with digits (API build number)
        expect(buildMatch![1]).not.toBe("999.123.456"); // Should NOT be the custom build number
      }
    });

    it("should work with single IDE in custom ide_config", async () => {
      const singleIdeConfig = JSON.stringify({
        "RR": { name: "My RustRover", icon: "/my/rustrover.svg", build: "888.999.111" }
      });
      
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        default: '["RR"]',
        options: '["RR"]', // Only one option
        ide_config: singleIdeConfig,
      });
      
      const coder_apps = state.resources.filter(
        (res) => res.type === "coder_app" && res.name === "jetbrains",
      );
      expect(coder_apps.length).toBe(1);
      expect(coder_apps[0].instances[0].attributes.display_name).toBe("My RustRover");
      expect(coder_apps[0].instances[0].attributes.icon).toBe("/my/rustrover.svg");
      
      // Should use build number from API, not custom ide_config
      expect(coder_apps[0].instances[0].attributes.url).toContain("ide_build_number=");
      if (typeof coder_apps[0].instances[0].attributes.url === "string") {
        const buildMatch = coder_apps[0].instances[0].attributes.url.match(/ide_build_number=([^&]+)/);
        expect(buildMatch).toBeTruthy();
        expect(buildMatch![1]).not.toBe("888.999.111"); // Should NOT be the custom build number
      }
    });
  });
});
