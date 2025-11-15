import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("aws-cli", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output version is 'latest'", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.aws_cli_version.value).toBe("latest");
  });

  it("output version matches specified version", async () => {
    const version = "2.15.0";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      aws_cli_version: version,
    });
    expect(state.outputs.aws_cli_version.value).toBe(version);
  });

  it("accepts custom install directory", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_directory: "/home/coder/.local",
    });
    expect(state.resources).toHaveLength(1);
  });

  it("accepts architecture parameter", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      architecture: "x86_64",
    });
    expect(state.resources).toHaveLength(1);
  });

  it("accepts verify_signature parameter", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      verify_signature: "true",
    });
    expect(state.resources).toHaveLength(1);
  });
});
