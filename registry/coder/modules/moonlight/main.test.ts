import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const allowedStreamingServers = ["sunshine", "gamestream"] as const;
type AllowedStreamingServer = (typeof allowedStreamingServers)[number];

type TestVariables = Readonly<{
  agent_id: string;
  streaming_server?: AllowedStreamingServer;
  port?: number;
  sunshine_version?: string;
  enable_audio?: boolean;
  enable_gamepad?: boolean;
  resolution?: string;
  fps?: number;
  bitrate?: number;
}>;

describe("Moonlight", async () => {
  await runTerraformInit(import.meta.dir);
  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "test-agent-id",
  });

  it("Successfully installs with sunshine (default)", async () => {
    await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      streaming_server: "sunshine",
    });
  });

  it("Successfully installs with gamestream", async () => {
    await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      streaming_server: "gamestream",
    });
  });

  it("Successfully installs with custom configuration", async () => {
    await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "test-agent-id",
      streaming_server: "sunshine",
      port: 48000,
      resolution: "2560x1440",
      fps: 120,
      bitrate: 50,
      enable_audio: false,
      enable_gamepad: false,
    });
  });

  it("Validates streaming server options", async () => {
    for (const server of allowedStreamingServers) {
      await runTerraformApply<TestVariables>(import.meta.dir, {
        agent_id: "test-agent-id",
        streaming_server: server,
      });
    }
  });
});
