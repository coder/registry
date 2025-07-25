import {
  test,
  afterEach,
  expect,
  describe,
  setDefaultTimeout,
  beforeAll,
} from "bun:test";
import { execContainer, runTerraformInit } from "~test";
import {
  setupContainer,
  loadTestFile,
  writeExecutable,
  execModuleScript,
  expectAgentAPIStarted,
} from "./test-util";

let cleanupFunctions: (() => Promise<void>)[] = [];

const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};

afterEach(async () => {
  const cleanupFnsCopy = cleanupFunctions.slice().reverse();
  cleanupFunctions = [];
  for (const cleanup of cleanupFnsCopy) {
    try {
      await cleanup();
    } catch (error) {
      console.error("Error during cleanup:", error);
    }
  }
});

const moduleDir = import.meta.dir;

beforeAll(async () => {
  await runTerraformInit(moduleDir);
});

describe("codex", () => {
  test("creates codex module with default configuration", async () => {
    const { id, coderScript, cleanup } = await setupContainer({
      moduleDir,
      image: "codercom/enterprise-node:latest",
    });
    registerCleanup(cleanup);

    // Execute the module script to install the mock CLI
    const scriptResult = await execModuleScript({
      containerId: id,
      coderScript,
    });
    expect(scriptResult.exitCode).toBe(0);

    // Test that the module installs correctly
    const result = await execContainer(id, ["which", "codex-cli"]);
    expect(result.exitCode).toBe(0);
  });

  test("creates codex module with custom configuration", async () => {
    const { id, coderScript, cleanup } = await setupContainer({
      moduleDir,
      image: "codercom/enterprise-node:latest",
      vars: {
        openai_model: "gpt-4",
        temperature: "0.7",
        max_tokens: "2048",
        folder: "/workspace",
        install_codex: "true",
        codex_version: "latest",
        order: "1",
        group: "AI Tools",
      },
    });
    registerCleanup(cleanup);

    // Execute the module script to install the mock CLI
    const scriptResult = await execModuleScript({
      containerId: id,
      coderScript,
    });
    expect(scriptResult.exitCode).toBe(0);

    // Test that the module installs correctly with custom configuration
    const result = await execContainer(id, ["which", "codex-cli"]);
    expect(result.exitCode).toBe(0);

    // Test that configuration is properly set
    const configResult = await execContainer(id, ["test", "-f", "/home/coder/.config/codex/config.toml"]);
    expect(configResult.exitCode).toBe(0);
  });

  test("creates codex module with custom API key", async () => {
    const { id, coderScript, cleanup } = await setupContainer({
      moduleDir,
      image: "codercom/enterprise-node:latest",
      vars: {
        openai_api_key: "sk-test-api-key",
        openai_model: "gpt-3.5-turbo",
      },
    });
    registerCleanup(cleanup);

    // Execute the module script to install the mock CLI
    const scriptResult = await execModuleScript({
      containerId: id,
      coderScript,
    });
    expect(scriptResult.exitCode).toBe(0);

    // Test that the module installs correctly
    const result = await execContainer(id, ["which", "codex-cli"]);
    expect(result.exitCode).toBe(0);
  });

  test("creates codex module with installation disabled", async () => {
    const { id, cleanup } = await setupContainer({
      moduleDir,
      image: "codercom/enterprise-node:latest",
      vars: {
        install_codex: "false",
      },
    });
    registerCleanup(cleanup);

    // Test that codex-cli is not installed when disabled
    const result = await execContainer(id, ["which", "codex-cli"]);
    expect(result.exitCode).toBe(1);
  });

  test("validates temperature range", async () => {
    // Test with invalid temperature (should fail during terraform plan/apply)
    try {
      await setupContainer({
        moduleDir,
        image: "codercom/enterprise-node:latest",
        vars: {
          temperature: "2.5", // Invalid - should be between 0.0 and 2.0
        },
      });
      expect(true).toBe(false); // Should not reach here
    } catch (error) {
      expect((error as Error).message).toContain("Temperature must be between 0.0 and 2.0");
    }
  });

  test("validates max_tokens range", async () => {
    // Test with invalid max_tokens (should fail during terraform plan/apply)
    try {
      await setupContainer({
        moduleDir,
        image: "codercom/enterprise-node:latest",
        vars: {
          max_tokens: "5000", // Invalid - should be between 1 and 4096
        },
      });
      expect(true).toBe(false); // Should not reach here
    } catch (error) {
      expect((error as Error).message).toContain("Max tokens must be between 1 and 4096");
    }
  });
});
