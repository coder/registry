import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type scriptOutput,
  type TerraformState,
} from "~test";

const executeScriptInContainer = async (
  state: TerraformState,
  image: string,
  before?: string,
): Promise<scriptOutput> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);
  await execContainer(id, ["sh", "-c", "apk add --no-cache bash >/dev/null"]);
  if (before) {
    await execContainer(id, ["sh", "-c", before]);
  }
  const resp = await execContainer(id, ["bash", "-c", instance.script]);
  return {
    exitCode: resp.exitCode,
    stdout: resp.stdout.trim().split("\n"),
    stderr: resp.stderr.trim().split("\n"),
  };
};

// Drops a fake `git` onto PATH that prints each argv entry on its own line.
// Lets tests prove that arguments (including ones with embedded spaces) reach
// `git clone` as single argv tokens, which the echo line cannot show because
// it joins with spaces.
const installFakeGit = [
  "cat > /usr/local/bin/git <<'SHIM'",
  "#!/bin/sh",
  'for arg in "$@"; do',
  '  printf "argv:%s\\n" "$arg"',
  "done",
  "SHIM",
  "chmod +x /usr/local/bin/git",
].join("\n");

describe("git-clone", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    url: "foo",
  });

  it("fails without git", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "some-url",
    });
    const output = await executeScriptInContainer(state, "alpine");
    expect(output.exitCode).toBe(1);
    expect(output.stdout).toEqual(["Git is not installed!"]);
  });

  it("runs with git", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
    });
    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.stdout).toContain("Creating directory /root/fake-url...");
    expect(output.stdout).toContain("Cloning fake-url to /root/fake-url...");
    expect(output.exitCode).not.toBe(0);
    expect(output.stdout.join(" ")).toContain("fatal");
    expect(output.stdout.join(" ")).toContain("fake-url");
  });

  it("repo_dir should match repo name for https", async () => {
    const url = "https://github.com/coder/coder.git";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/coder");
    expect(state.outputs.folder_name.value).toEqual("coder");
    expect(state.outputs.clone_url.value).toEqual(url);
    expect(state.outputs.web_url.value).toEqual(url);
    expect(state.outputs.branch_name.value).toEqual("");
  });

  it("repo_dir should match repo name for https without .git", async () => {
    const url = "https://github.com/coder/coder";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/coder");
    expect(state.outputs.clone_url.value).toEqual(url);
    expect(state.outputs.web_url.value).toEqual(url);
    expect(state.outputs.branch_name.value).toEqual("");
  });

  it("repo_dir should match repo name for ssh", async () => {
    const url = "git@github.com:coder/coder.git";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/coder");
    expect(state.outputs.git_provider.value).toEqual("");
    expect(state.outputs.clone_url.value).toEqual(url);
    const https_url = "https://github.com/coder/coder.git";
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("");
  });

  it("repo_dir should match base_dir/folder_name", async () => {
    const url = "git@github.com:coder/coder.git";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      folder_name: "foo",
      url,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/foo");
    expect(state.outputs.folder_name.value).toEqual("foo");
    expect(state.outputs.clone_url.value).toEqual(url);
    const https_url = "https://github.com/coder/coder.git";
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("");
  });

  it("branch_name should not include query string", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "https://gitlab.com/mike.brew/repo-tests.log/-/tree/feat/branch?ref_type=heads",
    });
    expect(state.outputs.repo_dir.value).toEqual("~/repo-tests.log");
    expect(state.outputs.folder_name.value).toEqual("repo-tests.log");
    const https_url = "https://gitlab.com/mike.brew/repo-tests.log";
    expect(state.outputs.clone_url.value).toEqual(https_url);
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("feat/branch");
  });

  it("branch_name should not include fragments", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url: "https://gitlab.com/mike.brew/repo-tests.log/-/tree/feat/branch#name",
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/repo-tests.log");
    const https_url = "https://gitlab.com/mike.brew/repo-tests.log";
    expect(state.outputs.clone_url.value).toEqual(https_url);
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("feat/branch");
  });

  it("gitlab url with branch should match", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url: "https://gitlab.com/mike.brew/repo-tests.log/-/tree/feat/branch",
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/repo-tests.log");
    expect(state.outputs.git_provider.value).toEqual("gitlab");
    const https_url = "https://gitlab.com/mike.brew/repo-tests.log";
    expect(state.outputs.clone_url.value).toEqual(https_url);
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("feat/branch");
  });

  it("github url with branch should match", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url: "https://github.com/michaelbrewer/repo-tests.log/tree/feat/branch",
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/repo-tests.log");
    expect(state.outputs.git_provider.value).toEqual("github");
    const https_url = "https://github.com/michaelbrewer/repo-tests.log";
    expect(state.outputs.clone_url.value).toEqual(https_url);
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("feat/branch");
  });

  it("self-host git url with branch should match", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url: "https://git.example.com/example/project/-/tree/feat/example",
      git_providers: `
      {
        "https://git.example.com/" = {
          provider = "gitlab"
        }
      }`,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/project");
    expect(state.outputs.git_provider.value).toEqual("gitlab");
    const https_url = "https://git.example.com/example/project";
    expect(state.outputs.clone_url.value).toEqual(https_url);
    expect(state.outputs.web_url.value).toEqual(https_url);
    expect(state.outputs.branch_name.value).toEqual("feat/example");
  });

  it("handle unsupported git provider configuration", async () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        url: "foo",
        git_providers: `
        {
          "https://git.example.com/" = {
            provider = "bitbucket"
          }
        }`,
      });
    };
    expect(t).toThrow('Allowed values for provider are "github" or "gitlab".');
  });

  it("handle unknown git provider url", async () => {
    const url = "https://git.unknown.com/coder/coder";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      base_dir: "/tmp",
      url,
    });
    expect(state.outputs.repo_dir.value).toEqual("/tmp/coder");
    expect(state.outputs.clone_url.value).toEqual(url);
    expect(state.outputs.web_url.value).toEqual(url);
    expect(state.outputs.branch_name.value).toEqual("");
  });

  it("runs with github clone with switch to feat/branch", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "https://github.com/michaelbrewer/repo-tests.log/tree/feat/branch",
    });
    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "Creating directory /root/repo-tests.log...",
    );
    expect(output.stdout).toContain(
      "Cloning https://github.com/michaelbrewer/repo-tests.log to /root/repo-tests.log on branch feat/branch...",
    );
  });

  it("runs with gitlab clone with switch to feat/branch", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "https://gitlab.com/mike.brew/repo-tests.log/-/tree/feat/branch",
    });
    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "Creating directory /root/repo-tests.log...",
    );
    expect(output.stdout).toContain(
      "Cloning https://gitlab.com/mike.brew/repo-tests.log to /root/repo-tests.log on branch feat/branch...",
    );
  });

  it("runs with github clone with branch_name set to feat/branch", async () => {
    const url = "https://github.com/michaelbrewer/repo-tests.log";
    const branch_name = "feat/branch";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url,
      branch_name,
    });
    expect(state.outputs.repo_dir.value).toEqual("~/repo-tests.log");
    expect(state.outputs.clone_url.value).toEqual(url);
    expect(state.outputs.web_url.value).toEqual(url);
    expect(state.outputs.branch_name.value).toEqual(branch_name);

    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "Creating directory /root/repo-tests.log...",
    );
    expect(output.stdout).toContain(
      "Cloning https://github.com/michaelbrewer/repo-tests.log to /root/repo-tests.log on branch feat/branch...",
    );
  });

  it("runs post-clone script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      base_dir: "/tmp",
      post_clone_script: "echo 'Post-clone script executed'",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      "mkdir -p /tmp/fake-url && echo 'existing' > /tmp/fake-url/file.txt",
    );
    expect(output.stdout).toContain("Running post-clone script...");
    expect(output.stdout).toContain("Post-clone script executed");
  });

  it("runs pre-clone script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      pre_clone_script: "echo 'Pre-clone script executed'",
    });
    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.stdout).toContain("Running pre-clone script...");
    expect(output.stdout).toContain("Pre-clone script executed");
    expect(output.stdout).toContain("Cloning fake-url to /root/fake-url...");
  });

  it("fails when pre-clone script fails", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      pre_clone_script: "echo 'Pre-clone script failed'; exit 42",
    });
    const output = await executeScriptInContainer(state, "alpine/git");
    expect(output.exitCode).toBe(42);
    expect(output.stdout).toContain("Running pre-clone script...");
    expect(output.stdout).toContain("Pre-clone script failed");
    expect(output.stdout).not.toContain(
      "Cloning fake-url to /root/fake-url...",
    );
  });

  it("defaults extra_args to empty", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      installFakeGit,
    );
    // With no extra_args the only argv tokens should be clone, url, path.
    expect(output.stdout.join("\n")).toContain(
      ["argv:clone", "argv:fake-url", "argv:/root/fake-url"].join("\n"),
    );
  });

  it("passes extra_args to git clone", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      extra_args: JSON.stringify([
        "--recurse-submodules",
        "--jobs=8",
        "--config=user.name=Coder User",
        "-c",
        "core.sshCommand=ssh -i /tmp/key",
      ]),
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      installFakeGit,
    );
    expect(output.exitCode).toBe(0);
    expect(output.stdout.join("\n")).toContain(
      [
        "argv:clone",
        "argv:--recurse-submodules",
        "argv:--jobs=8",
        "argv:--config=user.name=Coder User",
        "argv:-c",
        "argv:core.sshCommand=ssh -i /tmp/key",
        "argv:fake-url",
        "argv:/root/fake-url",
      ].join("\n"),
    );
  });

  it("passes extra_args alongside branch_name in the correct order", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      branch_name: "feat/branch",
      extra_args: JSON.stringify([
        "--recurse-submodules",
        "--config=user.name=Coder User",
      ]),
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      installFakeGit,
    );
    expect(output.exitCode).toBe(0);
    expect(output.stdout.join("\n")).toContain(
      [
        "argv:clone",
        "argv:--recurse-submodules",
        "argv:--config=user.name=Coder User",
        "argv:-b",
        "argv:feat/branch",
        "argv:fake-url",
        "argv:/root/fake-url",
      ].join("\n"),
    );
  });

  it("writes output to logs/clone.log under module directory", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
    });
    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/git");
    await execContainer(id, ["sh", "-c", "apk add --no-cache bash >/dev/null"]);
    await execContainer(id, ["bash", "-c", instance.script]);
    const log = await execContainer(id, [
      "bash",
      "-c",
      "cat /root/.coder-modules/coder/git-clone/*/logs/clone.log",
    ]);
    expect(log.exitCode).toBe(0);
    expect(log.stdout).toContain("Cloning fake-url to /root/fake-url...");
  });

  it("adds SSH host key to known_hosts for SSH URLs", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "git@github.com:coder/coder.git",
      base_dir: "/tmp",
    });
    const setupFakeTools = [
      installFakeGit,
      "cat > /usr/local/bin/ssh-keyscan <<'SHIM'",
      "#!/bin/sh",
      "echo 'github.com ssh-rsa AAAAB3NzaC1yc2EFAKE'",
      "SHIM",
      "chmod +x /usr/local/bin/ssh-keyscan",
    ].join("\n");
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      setupFakeTools,
    );
    expect(output.stdout).toContain(
      "Adding host key for github.com to known_hosts...",
    );
    expect(output.stdout).toContain(
      "Host key for github.com added to known_hosts.",
    );
    expect(output.exitCode).toBe(0);
  });

  it("uses StrictHostKeyChecking=accept-new when ssh-keyscan is unavailable for SSH URLs", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "git@github.com:coder/coder.git",
      base_dir: "/tmp",
    });
    const setupWithoutSshKeyscan = [
      installFakeGit,
      "rm -f /usr/bin/ssh-keyscan /usr/local/bin/ssh-keyscan 2>/dev/null || true",
    ].join("\n");
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      setupWithoutSshKeyscan,
    );
    expect(output.stdout).toContain(
      "Adding host key for github.com to known_hosts...",
    );
    expect(output.stdout).toContain(
      "ssh-keyscan not available. Using StrictHostKeyChecking=accept-new.",
    );
    expect(output.exitCode).toBe(0);
  });

  it("skips SSH host key scan when host is already in known_hosts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "git@github.com:coder/coder.git",
      base_dir: "/tmp",
    });
    const setupWithExistingKey = [
      installFakeGit,
      "mkdir -p /root/.ssh && chmod 700 /root/.ssh",
      "echo 'github.com ssh-rsa AAAAB3NzaC1yc2EEXISTING' >> /root/.ssh/known_hosts",
      "chmod 600 /root/.ssh/known_hosts",
    ].join("\n");
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      setupWithExistingKey,
    );
    expect(output.stdout).not.toContain(
      "Adding host key for github.com to known_hosts...",
    );
    expect(output.exitCode).toBe(0);
  });

  it("fails when post-clone script fails", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      url: "fake-url",
      base_dir: "/tmp",
      post_clone_script: "echo 'Post-clone script failed'; exit 43",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/git",
      "mkdir -p /tmp/fake-url && echo 'existing' > /tmp/fake-url/file.txt",
    );
    expect(output.exitCode).toBe(43);
    expect(output.stdout).toContain("Running post-clone script...");
    expect(output.stdout).toContain("Post-clone script failed");
  });
});
