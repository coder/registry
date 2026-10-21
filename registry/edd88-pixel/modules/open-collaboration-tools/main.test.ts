import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("open-collaboration-tools", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    server_url: "https://oct.example.com",
  });

  it("exposes defaults for web IDE composition", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      server_url: "https://oct.example.com",
    });

    expect(state.outputs.extensions.value).toEqual([
      "typefox.open-collaboration-tools@0.3.9",
    ]);
    expect(state.outputs.settings.value).toEqual({
      "oct.alwaysAskToOverrideServerUrl": false,
      "oct.files.exclude": ["**/.env"],
      "oct.joinAcceptMode": "prompt",
      "oct.joinAllowlist": [],
      "oct.serverUrl": "https://oct.example.com/",
    });
  });

  it("supports an extension already installed in the image", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      server_url: "https://oct.example.com",
      install_extension: false,
    });

    expect(state.outputs.extensions.value).toEqual([]);
  });

  it("preserves a configured collaboration policy", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      server_url: "http://localhost:8100/api",
      extension_id: "internal.open-collaboration-tools",
      extension_version: "0.3.9-internal.1",
      always_ask_to_override_server_url: true,
      join_accept_mode: "allowlist",
      join_allowlist: '["alice","bob"]',
      excluded_files: '["**/.env","**/*.pem"]',
    });

    expect(state.outputs.extensions.value).toEqual([
      "internal.open-collaboration-tools@0.3.9-internal.1",
    ]);
    expect(state.outputs.settings.value).toEqual({
      "oct.alwaysAskToOverrideServerUrl": true,
      "oct.files.exclude": ["**/.env", "**/*.pem"],
      "oct.joinAcceptMode": "allowlist",
      "oct.joinAllowlist": ["alice", "bob"],
      "oct.serverUrl": "http://localhost:8100/api/",
    });
  });
});
