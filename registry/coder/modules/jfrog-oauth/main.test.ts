import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
} from "~test";

describe("jfrog-oauth", async () => {
  type TestVariables = {
    agent_id: string;
    jfrog_url: string;
    package_managers: string;

    username_field?: string;
    jfrog_server_id?: string;
    external_auth_id?: string;
    configure_code_server?: boolean;
  };

  await runTerraformInit(import.meta.dir);

  const fakeFrogApi = "localhost:8081/artifactory/api";
  const fakeFrogUrl = "http://localhost:8081";
  const user = "default";

  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "some-agent-id",
    jfrog_url: fakeFrogUrl,
    package_managers: "{}",
  });

  it("generates an npmrc with scoped repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        npm: ["global", "@foo:foo", "@bar:bar"],
      }),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    const npmrcStanza = `cat << EOF > ~/.npmrc
email=${user}@example.com
registry=http://${fakeFrogApi}/npm/global
//${fakeFrogApi}/npm/global/:_authToken=
@foo:registry=http://${fakeFrogApi}/npm/foo
//${fakeFrogApi}/npm/foo/:_authToken=
@bar:registry=http://${fakeFrogApi}/npm/bar
//${fakeFrogApi}/npm/bar/:_authToken=

EOF`;
    expect(coderScript.script).toContain(npmrcStanza);
    expect(coderScript.script).toContain(
      'jf npmc --global --repo-resolve "global"',
    );
    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured npm',
    );
  });

  it("generates a pip config with extra-indexes", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        pypi: ["global", "foo", "bar"],
      }),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    const pipStanza = `cat << EOF > ~/.pip/pip.conf
[global]
index-url = https://${user}:@${fakeFrogApi}/pypi/global/simple
extra-index-url =
    https://${user}:@${fakeFrogApi}/pypi/foo/simple
    https://${user}:@${fakeFrogApi}/pypi/bar/simple

EOF`;
    expect(coderScript.script).toContain(pipStanza);
    expect(coderScript.script).toContain(
      'jf pipc --global --repo-resolve "global"',
    );
    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured pypi',
    );
  });

  it("registers multiple docker repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        docker: ["foo.jfrog.io", "bar.jfrog.io", "baz.jfrog.io"],
      }),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    const dockerStanza = ["foo", "bar", "baz"]
      .map((r) => `register_docker "${r}.jfrog.io"`)
      .join("\n");
    expect(coderScript.script).toContain(dockerStanza);
    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured docker',
    );
  });

  it("sets goproxy with multiple repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        go: ["foo", "bar", "baz"],
      }),
    });
    const proxyEnv = findResourceInstance(state, "coder_env", "goproxy");
    const proxies = ["foo", "bar", "baz"]
      .map((r) => `https://${user}:@${fakeFrogApi}/go/${r}`)
      .join(",");
    expect(proxyEnv.value).toEqual(proxies);

    const coderScript = findResourceInstance(state, "coder_script");
    expect(coderScript.script).toContain(
      'jf goc --global --repo-resolve "foo"',
    );
    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured go',
    );
  });

  it("generates a conda config with multiple repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        conda: ["conda-main", "conda-secondary", "conda-local"],
      }),
    });
    const coderScript = findResourceInstance(state, "coder_script");
    const condaStanza = `cat << EOF > ~/.condarc
channels:
  - https://${user}:@${fakeFrogApi}/conda/conda-main
  - https://${user}:@${fakeFrogApi}/conda/conda-secondary
  - https://${user}:@${fakeFrogApi}/conda/conda-local
  - defaults
ssl_verify: true

EOF`;
    expect(coderScript.script).toContain(condaStanza);
    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured conda',
    );
  });
  it("generates a maven settings.xml with multiple repos", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "some-agent-id",
      jfrog_url: fakeFrogUrl,
      package_managers: JSON.stringify({
        maven: ["central", "snapshots", "local"],
      }),
    });

    const coderScript = findResourceInstance(state, "coder_script");

    expect(coderScript.script).toContain(
      'jf mvnc --global --repo-resolve "central"',
    );

    expect(coderScript.script).toContain("<servers>");
    expect(coderScript.script).toContain("<id>central</id>");
    expect(coderScript.script).toContain("<id>snapshots</id>");
    expect(coderScript.script).toContain("<id>local</id>");

    expect(coderScript.script).toContain(
      "<url>http://localhost:8081/artifactory/central</url>",
    );
    expect(coderScript.script).toContain(
      "<url>http://localhost:8081/artifactory/snapshots</url>",
    );
    expect(coderScript.script).toContain(
      "<url>http://localhost:8081/artifactory/local</url>",
    );

    expect(coderScript.script).toContain(
      'if [ -z "YES" ]; then\n  not_configured maven',
    );
  });
});
