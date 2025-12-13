import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("zed", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("creates settings file with correct JSON", async () => {
    const settings = {
      theme: "One Dark",
      buffer_font_size: 14,
      vim_mode: true,
      telemetry: {
        diagnostics: false,
        metrics: false,
      },
      // Test special characters: single quotes, backslashes, URLs
      message: "it's working",
      path: "C:\\Users\\test",
      api_url: "https://api.example.com/v1?token=abc&user=test",
    };

    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: JSON.stringify(settings),
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine:latest");

    try {
      const result = await execContainer(id, ["sh", "-c", instance.script]);
      expect(result.exitCode).toBe(0);

      const catResult = await execContainer(id, [
        "cat",
        "/root/.config/zed/settings.json",
      ]);
      expect(catResult.exitCode).toBe(0);

      const written = JSON.parse(catResult.stdout.trim());
      expect(written).toEqual(settings);
    } finally {
      await removeContainer(id);
    }
  }, 30000);

  it("exits early with empty settings", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: "",
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine:latest");

    try {
      const result = await execContainer(id, ["sh", "-c", instance.script]);
      expect(result.exitCode).toBe(0);

      // Settings file should not be created
      const catResult = await execContainer(id, [
        "cat",
        "/root/.config/zed/settings.json",
      ]);
      expect(catResult.exitCode).not.toBe(0);
    } finally {
      await removeContainer(id);
    }
  }, 30000);
});
