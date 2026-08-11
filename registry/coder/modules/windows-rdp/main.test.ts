import { describe, expect, it } from "bun:test";
import {
  type TerraformState,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

type TestVariables = Readonly<{
  agent_id: string;
  share?: string;
  admin_username?: string;
  admin_password?: string;
}>;

function findWindowsRdpScript(state: TerraformState): string | null {
  for (const resource of state.resources) {
    const isRdpScriptResource =
      resource.type === "coder_script" && resource.name === "windows-rdp";

    if (!isRdpScriptResource) {
      continue;
    }

    for (const instance of resource.instances) {
      if (
        instance.attributes.display_name === "windows-rdp" &&
        typeof instance.attributes.script === "string"
      ) {
        return instance.attributes.script;
      }
    }
  }

  return null;
}

/**
 * Extracts the username and password the module injected into the JS patch
 * file.
 *
 * The values are injected as JSON-escaped content inside double-quoted JS
 * string literals, so the matched literals are parsed with JSON.parse to get
 * the original values back. The regex stays verbose and pedantic on purpose:
 * it validates the structure of the form entries object and, by only matching
 * non-quote characters or escape pairs, it cannot overshoot into later content.
 */
function extractFormFieldValues(rdpScript: string): {
  username?: string;
  password?: string;
} {
  const formEntryValuesRe =
    /username:\s*\{[\s\S]*?value:\s*(?<username>"(?:[^"\\]|\\.)*")[\s\S]*?password:\s*\{[\s\S]*?value:\s*(?<password>"(?:[^"\\]|\\.)*")/;

  const groups = formEntryValuesRe.exec(rdpScript)?.groups ?? {};

  return {
    username: groups.username && JSON.parse(groups.username),
    password: groups.password && JSON.parse(groups.password),
  };
}

/**
 * @todo It would be nice if we had a way to verify that the Devolutions root
 * HTML file is modified to include the import for the patched Coder script,
 * but the current test setup doesn't really make that viable
 */
describe("Web RDP", async () => {
  await runTerraformInit(import.meta.dir);
  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "foo",
  });

  it("Has the PowerShell script install Devolutions Gateway", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "foo",
    });

    const lines = findWindowsRdpScript(state)
      ?.split("\n")
      .filter(Boolean)
      .map((line) => line.trim());

    expect(lines).toEqual(
      expect.arrayContaining<string>([
        '$moduleName = "DevolutionsGateway"',
        // Default is "latest" to automatically get the newest version
        '$moduleVersion = "latest"',
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
        "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted",
        "Install-Module -Name $moduleName -Force",
      ]),
    );
  });

  it("Injects Terraform's username and password into the JS patch file", async () => {
    // Test that things work with the default username/password
    const defaultState = await runTerraformApply<TestVariables>(
      import.meta.dir,
      {
        agent_id: "foo",
      },
    );

    const defaultRdpScript = findWindowsRdpScript(defaultState);
    expect(defaultRdpScript).toBeString();

    expect(extractFormFieldValues(defaultRdpScript ?? "")).toEqual({
      username: "Administrator",
      password: "coderRDP!",
    });

    // Test that custom usernames/passwords are also forwarded correctly
    const customAdminUsername = "crouton";
    const customAdminPassword = "VeryVeryVeryVeryVerySecurePassword97!";
    const customizedState = await runTerraformApply<TestVariables>(
      import.meta.dir,
      {
        agent_id: "foo",
        admin_username: customAdminUsername,
        admin_password: customAdminPassword,
      },
    );

    const customRdpScript = findWindowsRdpScript(customizedState);
    expect(customRdpScript).toBeString();

    expect(extractFormFieldValues(customRdpScript ?? "")).toEqual({
      username: customAdminUsername,
      password: customAdminPassword,
    });
  });

  it("Preserves special characters in the password", async () => {
    // Covers the characters that break naive string interpolation in either the
    // JS patch file or the PowerShell installation script.
    const specialPassword = "N;JVO*U\\mL^a*P\"'`$&<>|{}[]%@:~";

    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      agent_id: "foo",
      admin_password: specialPassword,
    });

    const rdpScript = findWindowsRdpScript(state);
    expect(rdpScript).toBeString();

    // The JS patch file must receive the password verbatim once parsed.
    expect(extractFormFieldValues(rdpScript ?? "").password).toBe(
      specialPassword,
    );

    // PowerShell single-quoted strings are literal, and a literal single quote
    // is escaped by doubling it.
    expect(rdpScript).toContain(
      `Set-AdminPassword -adminPassword '${specialPassword.replace(/'/g, "''")}'`,
    );
  });
});
