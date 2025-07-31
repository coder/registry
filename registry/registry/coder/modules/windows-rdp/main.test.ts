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
        // Devolutions does versioning in the format year.minor.patch
        expect.stringMatching(/^\$moduleVersion = "\d{4}\.\d+\.\d+"$/),
        "Install-Module -Name $moduleName -RequiredVersion $moduleVersion -Force",
      ]),
    );
  });

  it("Injects Terraform's username and password into the JS patch file", async () => {
    /**
     * Using a regex as a quick-and-dirty way to get at the username and
     * password values.
     *
     * Tried going through the trouble of extracting out the form entries
     * variable from the main output, converting it from Prettier/JS-based JSON
     * text to universal JSON text, and exposing it as a parsed JSON value. That
     * got to be a bit too much, though.
     *
     * Regex is a little bit more verbose and pedantic than normal. Want to
     * have some basic safety nets for validating the structure of the form
     * entries variable after the JS file has had values injected. Even with all
     * the wildcard classes set to lazy mode, we want to make sure that they
     * don't overshoot and grab too much content.
     *
     * Written and tested via Regex101
     * @see {@link https://regex101.com/r/UMgQpv/2}
     */
    const formEntryValuesRe =
      /^const formFieldEntries = \{$.*?^\s+username: \{$.*?^\s*?querySelector.*?,$.*?^\s*value: "(?<username>.+?)",$.*?password: \{$.*?^\s+querySelector: .*?,$.*?^\s*value: "(?<password>.+?)",$.*?^};$/ms;

    // Test that things work with the default username/password
    const defaultState = await runTerraformApply<TestVariables>(
      import.meta.dir,
      {
        agent_id: "foo",
      },
    );

    const defaultRdpScript = findWindowsRdpScript(defaultState);
    expect(defaultRdpScript).toBeString();

    const defaultResultsGroup =
      formEntryValuesRe.exec(defaultRdpScript ?? "")?.groups ?? {};

    expect(defaultResultsGroup.username).toBe("Administrator");
    expect(defaultResultsGroup.password).toBe("coderRDP!");

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

    const customResultsGroup =
      formEntryValuesRe.exec(customRdpScript ?? "")?.groups ?? {};

    expect(customResultsGroup.username).toBe(customAdminUsername);
    expect(customResultsGroup.password).toBe(customAdminPassword);
  });
});
