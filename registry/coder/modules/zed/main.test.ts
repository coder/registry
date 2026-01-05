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

  it("merges settings with existing file when jq available", async () => {
    const existingSettings = {
      theme: "Solarized Dark",
      vim_mode: true,
    };

    const newSettings = {
      theme: "One Dark",
      buffer_font_size: 14,
    };

    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: JSON.stringify(newSettings),
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine:latest");

    try {
      // Install jq and create existing settings file
      await execContainer(id, ["apk", "add", "--no-cache", "jq"]);
      await execContainer(id, ["mkdir", "-p", "/root/.config/zed"]);
      await execContainer(id, [
        "sh",
        "-c",
        `echo '${JSON.stringify(existingSettings)}' > /root/.config/zed/settings.json`,
      ]);

      const result = await execContainer(id, ["sh", "-c", instance.script]);
      expect(result.exitCode).toBe(0);

      const catResult = await execContainer(id, [
        "cat",
        "/root/.config/zed/settings.json",
      ]);
      expect(catResult.exitCode).toBe(0);

      const merged = JSON.parse(catResult.stdout.trim());
      expect(merged.theme).toBe("One Dark"); // overwritten
      expect(merged.buffer_font_size).toBe(14); // added
      expect(merged.vim_mode).toBe(true); // preserved
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
