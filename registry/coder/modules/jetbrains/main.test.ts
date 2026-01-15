import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  readFileContainer,
  runContainer,
  execContainer,
  removeContainer,
  findResourceInstance,
} from "~test";

const BASH_IMAGE = "bash:latest";

describe("jetbrains-plugins", async () => {
  await runTerraformInit(import.meta.dir);

  it("does not create script when plugins empty", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/home/coder/project",
      default: '["GO"]',
      plugins: "[]",
    });

    const scripts = state.resources.filter((r) => r.type === "coder_script");
    expect(scripts.length).toBe(0);
  });

  it("creates script when plugins provided", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/home/coder/project",
      default: '["GO"]',
      plugins: '["org.jetbrains.plugins.github"]',
    });

    const script = findResourceInstance(state, "coder_script");
    expect(script).toBeDefined();
    expect(script.script).toContain("Setting up JetBrains plugins");
  });

  it("creates externalDependencies.xml with single plugin", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/tmp/project",
      default: '["GO"]',
      plugins: '["org.jetbrains.plugins.github"]',
    });

    const id = await runContainer(BASH_IMAGE);
    try {
      await execContainer(id, ["mkdir", "-p", "/tmp/project"]);

      const script = findResourceInstance(state, "coder_script");
      await execContainer(id, ["bash", "-c", script.script]);

      const xmlContent = await readFileContainer(
        id,
        "/tmp/project/.idea/externalDependencies.xml",
      );
      expect(xmlContent).toContain('<?xml version="1.0" encoding="UTF-8"?>');
      expect(xmlContent).toContain(
        '<plugin id="org.jetbrains.plugins.github" />',
      );
    } finally {
      await removeContainer(id);
    }
  });

  it("creates externalDependencies.xml with multiple plugins", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/tmp/project",
      default: '["GO"]',
      plugins:
        '["org.jetbrains.plugins.github", "Docker", "com.intellij.kubernetes"]',
    });

    const id = await runContainer(BASH_IMAGE);
    try {
      await execContainer(id, ["mkdir", "-p", "/tmp/project"]);

      const script = findResourceInstance(state, "coder_script");
      await execContainer(id, ["bash", "-c", script.script]);

      const xmlContent = await readFileContainer(
        id,
        "/tmp/project/.idea/externalDependencies.xml",
      );
      expect(xmlContent).toContain(
        '<plugin id="org.jetbrains.plugins.github" />',
      );
      expect(xmlContent).toContain('<plugin id="Docker" />');
      expect(xmlContent).toContain('<plugin id="com.intellij.kubernetes" />');
    } finally {
      await removeContainer(id);
    }
  });

  it("handles missing project directory gracefully", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/nonexistent/project",
      default: '["GO"]',
      plugins: '["org.jetbrains.plugins.github"]',
    });

    const id = await runContainer(BASH_IMAGE);
    try {
      const script = findResourceInstance(state, "coder_script");
      const result = await execContainer(id, ["bash", "-c", script.script]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("does not exist yet");
    } finally {
      await removeContainer(id);
    }
  });

  it("script exits early when no plugins specified", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/tmp/project",
      default: '["GO"]',
      plugins: '["test-plugin"]',
    });

    const script = findResourceInstance(state, "coder_script");
    const modifiedScript = script.script.replace(
      'PLUGINS="test-plugin"',
      'PLUGINS=""',
    );

    const id = await runContainer(BASH_IMAGE);
    try {
      const result = await execContainer(id, ["bash", "-c", modifiedScript]);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("No plugins specified");
    } finally {
      await removeContainer(id);
    }
  });

  it("starts background installer process", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      folder: "/tmp/project",
      default: '["GO"]',
      plugins: '["org.jetbrains.plugins.github"]',
    });

    const id = await runContainer(BASH_IMAGE);
    try {
      await execContainer(id, ["mkdir", "-p", "/tmp/project"]);

      const script = findResourceInstance(state, "coder_script");
      const result = await execContainer(id, ["bash", "-c", script.script]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Background installer running");
      expect(result.stdout).toContain("JetBrains plugin setup complete");

      const pidFile = await readFileContainer(
        id,
        "/tmp/jetbrains-plugin-installer.pid",
      );
      expect(pidFile.trim()).toMatch(/^\d+$/);
    } finally {
      await removeContainer(id);
    }
  });
});
