import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("tailscale", async () => {
  type TestVariables = {
    agent_id: string;
    auth_key?: string;
    tailscale_api_url?: string;
    oauth_client_id?: string;
    oauth_client_secret?: string;
    tailnet?: string;
    hostname?: string;
    tags?: string;
    ephemeral?: boolean;
    preauthorized?: boolean;
    networking_mode?: string;
    socks5_proxy_port?: number;
    http_proxy_port?: number;
    accept_dns?: boolean;
    accept_routes?: boolean;
    advertise_routes?: string;
    ssh?: boolean;
    extra_flags?: string;
    state_dir?: string;
  };

  await runTerraformInit(import.meta.dir);

  // Only agent_id has no default — all other vars are optional.
  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "some-agent-id",
  });

  // ── Outputs ───────────────────────────────────────────────────────────────

  it("uses explicit hostname", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      hostname: "my-workspace",
    });
    expect(state.outputs.hostname.value).toBe("my-workspace");
  });

  it("defaults state_dir to empty string", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
    });
    expect(state.outputs.state_dir.value).toBe("");
  });

  it("uses explicit state_dir", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      state_dir: "/tmp/tailscale-state",
    });
    expect(state.outputs.state_dir.value).toBe("/tmp/tailscale-state");
  });

  // ── Validation ────────────────────────────────────────────────────────────

  it("rejects invalid networking_mode", async () => {
    try {
      await runTerraformApply<TestVariables>(import.meta.dir, {
        agent_id: "some-agent-id",
        networking_mode: "invalid",
      });
      throw new Error("expected apply to fail");
    } catch (e) {
      expect(e).toBeInstanceOf(Error);
    }
  });

  it("accepts all valid networking modes", async () => {
    for (const mode of ["auto", "kernel", "userspace"]) {
      await runTerraformApply<TestVariables>(import.meta.dir, {
        agent_id: "some-agent-id",
        networking_mode: mode,
      });
    }
  });

  it("rejects tags without tag: prefix", async () => {
    try {
      await runTerraformApply<TestVariables>(import.meta.dir, {
        agent_id: "some-agent-id",
        tags: '["no-prefix"]',
      });
      throw new Error("expected apply to fail");
    } catch (e) {
      expect(e).toBeInstanceOf(Error);
    }
  });

  it("accepts tags with tag: prefix", async () => {
    await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      tags: '["tag:coder", "tag:staging"]',
    });
  });
});
