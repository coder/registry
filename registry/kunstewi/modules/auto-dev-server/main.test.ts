import { expect, it, describe } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  runContainer,
  removeContainer,
  execContainer,
  writeFileContainer,
  readFileContainer,
  TerraformState,
} from "../../../../test/test";

const moduleDir = import.meta.dir;

describe("auto-dev-server", () => {
  // Test required variables
  testRequiredVariables(moduleDir, {
    agent_id: "test-agent-id",
  });

  // Test basic module functionality
  it("should apply successfully with default values", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
    });

    // Verify the script resource was created
    const scriptResource = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "auto_dev_server"
    );
    expect(scriptResource).toBeDefined();
    expect(scriptResource?.instances[0].attributes.agent_id).toBe("test-agent-id");
    expect(scriptResource?.instances[0].attributes.display_name).toBe("Auto Development Server");
    expect(scriptResource?.instances[0].attributes.run_on_start).toBe(true);
  });

  // Test custom configuration
  it("should apply successfully with custom values", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace/projects",
      auto_start: false,
      port_range_start: 4000,
      port_range_end: 8000,
      log_level: "DEBUG",
    });

    const scriptResource = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "auto_dev_server"
    );
    expect(scriptResource).toBeDefined();
    
    // Check that the script contains our custom values
    const script = scriptResource?.instances[0].attributes.script as string;
    expect(script).toContain('PROJECT_DIR="/workspace/projects"');
    expect(script).toContain('AUTO_START="false"');
    expect(script).toContain('PORT_RANGE_START="4000"');
    expect(script).toContain('PORT_RANGE_END="8000"');
    expect(script).toContain('LOG_LEVEL="DEBUG"');
  });

  // Test script execution in container
  it("should execute script and detect Node.js project", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: true,
    });

    const containerId = await runContainer("ubuntu:22.04");
    
    try {
      // Install dependencies
      await execContainer(containerId, [
        "bash", "-c", 
        "apt-get update && apt-get install -y jq curl nodejs npm"
      ]);

      // Create a test Node.js project
      await writeFileContainer(containerId, "/workspace/package.json", JSON.stringify({
        name: "test-project",
        scripts: {
          start: "echo 'Server started' && sleep 10",
          dev: "echo 'Dev server started' && sleep 10"
        }
      }));

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      // Run the script
      const result = await execContainer(containerId, ["bash", "-c", script]);
      
      // Check that the script executed without errors
      expect(result.exitCode).toBe(0);
      
      // Wait a moment for processes to start
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Check if PID file was created
      const pidFile = await readFileContainer(containerId, "/root/.auto-dev-server-pids/test-project.pid");
      expect(pidFile).toBeDefined();
      
      // Check if log file was created
      const logFile = await readFileContainer(containerId, "/root/.auto-dev-server.log");
      expect(logFile).toContain("Found project: test-project");
      expect(logFile).toContain("Starting development server for test-project");
      
    } finally {
      await removeContainer(containerId);
    }
  });

  // Test Python project detection
  it("should detect and start Python Flask project", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: true,
    });

    const containerId = await runContainer("python:3.9-slim");
    
    try {
      // Install dependencies
      await execContainer(containerId, [
        "bash", "-c", 
        "apt-get update && apt-get install -y jq curl"
      ]);

      // Create a test Flask project
      await writeFileContainer(containerId, "/workspace/app.py", `
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello, World!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
      `);

      await writeFileContainer(containerId, "/workspace/requirements.txt", "flask==2.0.1");

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      const result = await execContainer(containerId, ["bash", "-c", script]);
      expect(result.exitCode).toBe(0);
      
      // Wait for processes to start
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      // Check if Flask process is running
      const processes = await execContainer(containerId, ["ps", "aux"]);
      expect(processes.stdout).toContain("flask");
      
    } finally {
      await removeContainer(containerId);
    }
  });

  // Test devcontainer integration
  it("should use devcontainer postStartCommand", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: true,
    });

    const containerId = await runContainer("ubuntu:22.04");
    
    try {
      // Install dependencies
      await execContainer(containerId, [
        "bash", "-c", 
        "apt-get update && apt-get install -y jq"
      ]);

      // Create devcontainer.json with postStartCommand
      await writeFileContainer(containerId, "/workspace/.devcontainer/devcontainer.json", JSON.stringify({
        name: "test-devcontainer",
        postStartCommand: "echo 'Custom post-start command executed' && sleep 5"
      }));

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      const result = await execContainer(containerId, ["bash", "-c", script]);
      expect(result.exitCode).toBe(0);
      
      // Check if the custom command was executed
      const logFile = await readFileContainer(containerId, "/root/.auto-dev-server.log");
      expect(logFile).toContain("Custom post-start command executed");
      
    } finally {
      await removeContainer(containerId);
    }
  });

  // Test port allocation
  it("should allocate different ports for multiple projects", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: true,
      port_range_start: 3000,
      port_range_end: 3010,
    });

    const containerId = await runContainer("node:16");
    
    try {
      // Create multiple Node.js projects
      await writeFileContainer(containerId, "/workspace/project1/package.json", JSON.stringify({
        name: "project1",
        scripts: { start: "echo 'Project 1 started' && sleep 10" }
      }));

      await writeFileContainer(containerId, "/workspace/project2/package.json", JSON.stringify({
        name: "project2", 
        scripts: { start: "echo 'Project 2 started' && sleep 10" }
      }));

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      const result = await execContainer(containerId, ["bash", "-c", script]);
      expect(result.exitCode).toBe(0);
      
      // Wait for processes to start
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      // Check that both projects got different ports
      const logFile = await readFileContainer(containerId, "/root/.auto-dev-server.log");
      expect(logFile).toContain("project1");
      expect(logFile).toContain("project2");
      
      // Check that different ports were allocated
      const portMatches = logFile.match(/Port: (\d+)/g);
      expect(portMatches).toBeDefined();
      expect(portMatches!.length).toBeGreaterThan(1);
      
      // Verify ports are different
      const ports = portMatches!.map(match => parseInt(match.split(": ")[1]));
      const uniquePorts = new Set(ports);
      expect(uniquePorts.size).toBeGreaterThan(1);
      
    } finally {
      await removeContainer(containerId);
    }
  });

  // Test cleanup functionality
  it("should cleanup dead processes", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: true,
    });

    const containerId = await runContainer("ubuntu:22.04");
    
    try {
      // Install dependencies
      await execContainer(containerId, [
        "bash", "-c", 
        "apt-get update && apt-get install -y jq"
      ]);

      // Create a PID file for a non-existent process
      await execContainer(containerId, [
        "bash", "-c", 
        "mkdir -p /root/.auto-dev-server-pids && echo 99999 > /root/.auto-dev-server-pids/test-project.pid"
      ]);

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      const result = await execContainer(containerId, ["bash", "-c", script]);
      expect(result.exitCode).toBe(0);
      
      // Check that the dead process PID file was cleaned up
      const logFile = await readFileContainer(containerId, "/root/.auto-dev-server.log");
      expect(logFile).toContain("Cleaning up dead process for test-project");
      
      // Verify PID file was removed
      const pidFileExists = await execContainer(containerId, [
        "test", "-f", "/root/.auto-dev-server-pids/test-project.pid"
      ]);
      expect(pidFileExists.exitCode).toBe(1); // File should not exist
      
    } finally {
      await removeContainer(containerId);
    }
  });

  // Test log level configuration
  it("should respect log level configuration", async () => {
    const state = await runTerraformApply(moduleDir, {
      agent_id: "test-agent-id",
      project_dir: "/workspace",
      auto_start: false, // Don't start servers, just test logging
      log_level: "DEBUG",
    });

    const containerId = await runContainer("ubuntu:22.04");
    
    try {
      // Install dependencies
      await execContainer(containerId, [
        "bash", "-c", 
        "apt-get update && apt-get install -y jq"
      ]);

      // Execute the auto-dev-server script
      const scriptResource = state.resources.find(
        (r) => r.type === "coder_script" && r.name === "auto_dev_server"
      );
      const script = scriptResource?.instances[0].attributes.script as string;
      
      const result = await execContainer(containerId, ["bash", "-c", script]);
      expect(result.exitCode).toBe(0);
      
      // Check that DEBUG level logging is working
      const logFile = await readFileContainer(containerId, "/root/.auto-dev-server.log");
      expect(logFile).toContain("[DEBUG]");
      
    } finally {
      await removeContainer(containerId);
    }
  });
});
