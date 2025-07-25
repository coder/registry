import { it, expect, describe } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "~test";

describe("full-stack-developer", async () => {
  await runTerraformInit(import.meta.dir);

  await testRequiredVariables(import.meta.dir, {});

  // Test default configuration
  describe("default configuration", () => {
    it("should create complete development environment", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      // Should create Docker container
      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);

      // Should create Coder agent
      const agents = state.resources.filter(
        (res) => res.type === "coder_agent" && res.name === "main"
      );
      expect(agents.length).toBe(1);

      // Should create development tools module
      const devTools = state.modules?.filter(
        (mod) => mod.address === "module.dev_tools[0]"
      );
      expect(devTools?.length).toBe(1);

      // Should create code-server module
      const codeServer = state.modules?.filter(
        (mod) => mod.address === "module.code_server[0]"
      );
      expect(codeServer?.length).toBe(1);

      // Should create JetBrains plugins module
      const jetbrains = state.modules?.filter(
        (mod) => mod.address === "module.jetbrains_with_plugins[0]"
      );
      expect(jetbrains?.length).toBe(1);

      // Should create dotfiles module
      const dotfiles = state.modules?.filter(
        (mod) => mod.address === "module.dotfiles[0]"
      );
      expect(dotfiles?.length).toBe(1);
    });

    it("should create proper parameters", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      // Should create all required parameters
      const parameters = state.resources.filter(
        (res) => res.type === "coder_parameter"
      );
      
      const parameterNames = parameters.map(p => p.name);
      expect(parameterNames).toContain("image");
      expect(parameterNames).toContain("repo_url");
      expect(parameterNames).toContain("jetbrains_ides");
      expect(parameterNames).toContain("dev_tools");

      // Check parameter defaults
      const devToolsParam = parameters.find(p => p.name === "dev_tools");
      expect(devToolsParam?.instances[0].attributes.default).toBe('["git","nodejs"]');

      const jetbrainsParam = parameters.find(p => p.name === "jetbrains_ides");
      expect(jetbrainsParam?.instances[0].attributes.default).toBe('["IU"]');
    });
  });

  // Test with custom configuration
  describe("custom configuration", () => {
    it("should work with custom parameters", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        image: "codercom/enterprise-python:ubuntu",
        dev_tools: JSON.stringify(["git", "python", "docker"]),
        jetbrains_ides: JSON.stringify(["PY", "IU"]),
        repo_url: "https://github.com/user/test-repo",
      });

      // Should create container with custom image
      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);

      // Should create git-clone module when repo_url is provided
      const gitClone = state.modules?.filter(
        (mod) => mod.address === "module.git_clone[0]"
      );
      expect(gitClone?.length).toBe(1);

      // Should create workspace metadata
      const metadata = state.resources.filter(
        (res) => res.type === "coder_metadata" && res.name === "workspace_info"
      );
      expect(metadata.length).toBe(1);
    });

    it("should handle different container images", async () => {
      const images = [
        "codercom/enterprise-base:ubuntu",
        "codercom/enterprise-node:ubuntu", 
        "codercom/enterprise-python:ubuntu",
        "codercom/enterprise-golang:ubuntu"
      ];

      for (const image of images) {
        const state = await runTerraformApply(import.meta.dir, {
          image: image,
        });

        const imageResources = state.resources.filter(
          (res) => res.type === "docker_image" && res.name === "main"
        );
        expect(imageResources.length).toBe(1);
        expect(imageResources[0].instances[0].attributes.name).toBe(image);
      }
    });
  });

  // Test git repository integration
  describe("git repository integration", () => {
    it("should create git-clone module when repo_url is provided", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        repo_url: "https://github.com/user/test-project",
      });

      const gitClone = state.modules?.filter(
        (mod) => mod.address === "module.git_clone[0]"
      );
      expect(gitClone?.length).toBe(1);
    });

    it("should not create git-clone module when repo_url is empty", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        repo_url: "",
      });

      const gitClone = state.modules?.filter(
        (mod) => mod.address?.includes("git_clone")
      );
      expect(gitClone?.length || 0).toBe(0);
    });
  });

  // Test plugin intelligence
  describe("plugin intelligence", () => {
    it("should configure plugins based on selected tools", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        dev_tools: JSON.stringify(["git", "python", "docker", "nodejs"]),
        jetbrains_ides: JSON.stringify(["IU", "PY"]),
      });

      // The template should be created successfully with intelligent plugin configuration
      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);

      // JetBrains module should be created
      const jetbrains = state.modules?.filter(
        (mod) => mod.address === "module.jetbrains_with_plugins[0]"
      );
      expect(jetbrains?.length).toBe(1);
    });

    it("should handle minimal tool selection", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        dev_tools: JSON.stringify(["git"]),
        jetbrains_ides: JSON.stringify(["IU"]),
      });

      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);
    });

    it("should handle maximum tool selection", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        dev_tools: JSON.stringify(["git", "docker", "nodejs", "python", "golang"]),
        jetbrains_ides: JSON.stringify(["IU", "PY", "WS", "GO", "PS", "RD", "CL", "RM", "RR"]),
      });

      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);
    });
  });

  // Test Docker configuration
  describe("docker configuration", () => {
    it("should create persistent volume", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      const volumes = state.resources.filter(
        (res) => res.type === "docker_volume" && res.name === "home_volume"
      );
      expect(volumes.length).toBe(1);

      const volume = volumes[0];
      expect(volume.instances[0].attributes.name).toMatch(/^coder-.+-home$/);
    });

    it("should configure container with proper labels", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);

      const container = containers[0];
      const labels = container.instances[0].attributes.labels;
      
      expect(labels).toBeDefined();
      expect(Array.isArray(labels)).toBe(true);
      
      // Check for required labels
      const labelMap = new Map();
      labels.forEach((label: any) => {
        labelMap.set(label.label, label.value);
      });
      
      expect(labelMap.has("coder.owner")).toBe(true);
      expect(labelMap.has("coder.owner_id")).toBe(true);
      expect(labelMap.has("coder.workspace_id")).toBe(true);
      expect(labelMap.has("coder.workspace_name")).toBe(true);
    });

    it("should mount Docker socket for development", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      const containers = state.resources.filter(
        (res) => res.type === "docker_container" && res.name === "workspace"
      );
      expect(containers.length).toBe(1);

      const container = containers[0];
      const volumes = container.instances[0].attributes.volumes;
      
      expect(Array.isArray(volumes)).toBe(true);
      
      // Should have home volume and docker socket
      const dockerSocketMount = volumes.find((v: any) => 
        v.container_path === "/var/run/docker.sock"
      );
      expect(dockerSocketMount).toBeDefined();
      expect(dockerSocketMount.host_path).toBe("/var/run/docker.sock");
    });
  });

  // Test agent configuration
  describe("agent configuration", () => {
    it("should create agent with proper metadata", async () => {
      const state = await runTerraformApply(import.meta.dir, {});

      const agents = state.resources.filter(
        (res) => res.type === "coder_agent" && res.name === "main"
      );
      expect(agents.length).toBe(1);

      const agent = agents[0];
      expect(agent.instances[0].attributes.os).toBe("linux");
      expect(agent.instances[0].attributes.login_before_ready).toBe(false);
      expect(agent.instances[0].attributes.startup_script_timeout).toBe(180);
      expect(agent.instances[0].attributes.startup_script_behavior).toBe("blocking");

      // Should have metadata for monitoring
      const metadata = agent.instances[0].attributes.metadata;
      expect(Array.isArray(metadata)).toBe(true);
      expect(metadata.length).toBeGreaterThan(0);

      const metadataKeys = metadata.map((m: any) => m.key);
      expect(metadataKeys).toContain("0_cpu_usage");
      expect(metadataKeys).toContain("1_ram_usage");
      expect(metadataKeys).toContain("3_home_disk");
    });
  });

  // Test workspace metadata
  describe("workspace metadata", () => {
    it("should create workspace metadata with configuration info", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        dev_tools: JSON.stringify(["git", "python"]),
        jetbrains_ides: JSON.stringify(["IU", "PY"]),
        repo_url: "https://github.com/user/test",
      });

      const metadata = state.resources.filter(
        (res) => res.type === "coder_metadata" && res.name === "workspace_info"
      );
      expect(metadata.length).toBe(1);

      const metadataItems = metadata[0].instances[0].attributes.item;
      expect(Array.isArray(metadataItems)).toBe(true);

      const itemMap = new Map();
      metadataItems.forEach((item: any) => {
        itemMap.set(item.key, item.value);
      });

      expect(itemMap.has("image")).toBe(true);
      expect(itemMap.has("selected_tools")).toBe(true);
      expect(itemMap.has("selected_ides")).toBe(true);
      expect(itemMap.has("repository")).toBe(true);
      expect(itemMap.has("configured_plugins")).toBe(true);

      expect(itemMap.get("selected_tools")).toBe("git, python");
      expect(itemMap.get("selected_ides")).toBe("IU, PY");
      expect(itemMap.get("repository")).toBe("https://github.com/user/test");
    });
  });
});