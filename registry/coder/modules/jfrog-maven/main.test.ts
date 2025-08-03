import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
} from "~test";

describe("jfrog-maven", async () => {
  type TestVariables = {
    agent_id: string;
    jfrog_url: string;
    maven_repositories?: string;

    username_field?: string;
    jfrog_server_id?: string;
    external_auth_id?: string;
    configure_code_server?: boolean;
  };

  await runTerraformInit(import.meta.dir);

  const fakeFrogApi = "localhost:8081/artifactory/api";
  const fakeFrogUrl = "http://localhost:8081";
  const user = "default";

  it("can run apply with required variables", async () => {
    testRequiredVariables<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
    });
  });

  it("configures maven with multiple repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      maven_repositories: JSON.stringify(["maven-local", "maven-remote", "maven-virtual"]),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    expect(coderScript.script).toContain(
      'jf mvc --global --repo-resolve "maven-local"',
    );
    expect(coderScript.script).toContain("mkdir -p ~/.m2");
    expect(coderScript.script).toContain("cat << EOF > ~/.m2/settings.xml");
  });

  it("skips maven configuration when no repos provided", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      maven_repositories: JSON.stringify([]),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    expect(coderScript.script).toContain("no Maven repositories are set, skipping Maven configuration");
  });
}); 