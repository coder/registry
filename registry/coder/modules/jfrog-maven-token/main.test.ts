import { serve } from "bun";
import { describe, expect, it } from "bun:test";
import {
  createJSONResponse,
  findResourceInstance,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
} from "~test";

describe("jfrog-maven-token", async () => {
  type TestVariables = {
    agent_id: string;
    jfrog_url: string;
    artifactory_access_token: string;
    maven_repositories?: string;

    token_description?: string;
    check_license?: boolean;
    refreshable?: boolean;
    expires_in?: number;
    username_field?: string;
    username?: string;
    jfrog_server_id?: string;
    configure_code_server?: boolean;
  };

  await runTerraformInit(import.meta.dir);

  // Run a fake JFrog server so the provider can initialize
  // correctly. This saves us from having to make remote requests!
  const fakeFrogHost = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      // See https://jfrog.com/help/r/jfrog-rest-apis/license-information
      if (url.pathname === "/artifactory/api/system/license")
        return createJSONResponse({
          type: "Commercial",
          licensedTo: "JFrog inc.",
          validThrough: "May 15, 2036",
        });
      if (url.pathname === "/access/api/v1/tokens")
        return createJSONResponse({
          token_id: "xxx",
          access_token: "xxx",
          scopes: "any",
        });
      return createJSONResponse({});
    },
    port: 0,
  });

  const fakeFrogApi = `${fakeFrogHost.hostname}:${fakeFrogHost.port}/artifactory/api`;
  const fakeFrogUrl = `http://${fakeFrogHost.hostname}:${fakeFrogHost.port}`;
  const user = "default";
  const token = "xxx";

  it("can run apply with required variables", async () => {
    testRequiredVariables<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      artifactory_access_token: "XXXX",
    });
  });

  it("configures maven with multiple repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      artifactory_access_token: "XXXX",
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
      artifactory_access_token: "XXXX",
      maven_repositories: JSON.stringify([]),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    expect(coderScript.script).toContain("no Maven repositories are set, skipping Maven configuration");
  });
}); 