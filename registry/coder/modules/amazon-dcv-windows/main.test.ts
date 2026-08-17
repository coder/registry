import { describe, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

type TestVariables = Readonly<{
  agent_id: string;
  admin_password?: string;
}>;

const assertCredentialRoundTrip = (
  actual: string | null,
  expected: string,
  context: string,
) => {
  if (actual !== expected) {
    throw new Error(`${context} did not preserve the credential`);
  }
};

const extractPowerShellPassword = (script: string): string | null => {
  const assignment = /^\$adminPassword = '((?:[^']|'')*)'[ \t]*\r?$/m.exec(
    script,
  );

  return assignment?.[1]?.replaceAll("''", "'") ?? null;
};

const renderCredentials = async (adminPassword?: string) => {
  const variables: TestVariables = {
    agent_id: "test-agent-id",
    ...(adminPassword === undefined ? {} : { admin_password: adminPassword }),
  };
  const state = await runTerraformApply<TestVariables>(
    import.meta.dir,
    variables,
  );
  const script = findResourceInstance(state, "coder_script", "install-dcv");
  const app = findResourceInstance(state, "coder_app", "web-dcv");

  return {
    appUrl: new URL(app.url),
    password: extractPowerShellPassword(script.script),
  };
};

describe("amazon-dcv-windows", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "test-agent-id",
  });

  it("preserves default credentials", async () => {
    const rendered = await renderCredentials();

    assertCredentialRoundTrip(
      rendered.password,
      "coderDCV!",
      "Default PowerShell rendering",
    );
    assertCredentialRoundTrip(
      rendered.appUrl.searchParams.get("username"),
      "Administrator",
      "Default URL username decoding",
    );
    assertCredentialRoundTrip(
      rendered.appUrl.searchParams.get("password"),
      "coderDCV!",
      "Default URL password decoding",
    );
  });

  it("preserves special characters in the PowerShell script", async () => {
    const specialPassword =
      String.raw`N;JVO*U\mL^a*P"` + "'" + "`" + "$&<>|#%+";
    const rendered = await renderCredentials(specialPassword);

    assertCredentialRoundTrip(
      rendered.password,
      specialPassword,
      "PowerShell rendering",
    );
  });

  it("preserves special characters in URL parameters", async () => {
    const specialPassword =
      String.raw`N;JVO*U\mL^a*P"` + "'" + "`" + "$&<>|#%+";
    const rendered = await renderCredentials(specialPassword);

    assertCredentialRoundTrip(
      rendered.appUrl.searchParams.get("username"),
      "Administrator",
      "URL username decoding",
    );
    assertCredentialRoundTrip(
      rendered.appUrl.searchParams.get("password"),
      specialPassword,
      "URL password decoding",
    );
  });
});
