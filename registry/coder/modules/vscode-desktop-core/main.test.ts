import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";
import { mkdtempSync, rmSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// hardcoded coder_app name in main.tf
const appName = "vscode-desktop";

const defaultVariables = {
  agent_id: "foo",
  coder_app_icon: "/icon/code.svg",
  coder_app_slug: "vscode",
  coder_app_display_name: "VS Code Desktop",
  protocol: "vscode",
};

describe("vscode-desktop-core", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, defaultVariables);

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, defaultVariables);
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === appName,
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("adds folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",
      ...defaultVariables,
    });

    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",
      open_recent: "true",
      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds folder but not open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",
      openRecent: "false",
      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      open_recent: "true",
      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      coder_app_order: "22",
      ...defaultVariables,
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === appName,
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });
});

describe("vscode-desktop-core extension script logic", async () => {
  await runTerraformInit(import.meta.dir);

  let tempDir: string;

  beforeAll(() => {
    tempDir = mkdtempSync(join(tmpdir(), "vscode-extensions-test-"));
  });

  afterAll(() => {
    if (tempDir && existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  const supportedIdes = [
    {
      protocol: "vscode",
      name: "VS Code",
      expectedUrls: [
        "marketplace.visualstudio.com/_apis/public/gallery/vscode/",
      ],
      marketplace: "Microsoft",
    },
    {
      protocol: "vscode-insiders",
      name: "VS Code Insiders",
      expectedUrls: [
        "marketplace.visualstudio.com/_apis/public/gallery/vscode/",
      ],
      marketplace: "Microsoft",
    },
    {
      protocol: "vscodium",
      name: "VSCodium",
      expectedUrls: ["open-vsx.org/api/"],
      marketplace: "Open VSX",
    },
    {
      protocol: "cursor",
      name: "Cursor",
      expectedUrls: ["open-vsx.org/api/"],
      marketplace: "Open VSX",
    },
    {
      protocol: "windsurf",
      name: "WindSurf",
      expectedUrls: ["open-vsx.org/api/"],
      marketplace: "Open VSX",
    },
    {
      protocol: "kiro",
      name: "Kiro",
      expectedUrls: ["open-vsx.org/api/"],
      marketplace: "Open VSX",
    },
  ];

  // Test extension script generation and IDE-specific marketplace logic
  for (const ide of supportedIdes) {
    it(`should use correct marketplace for ${ide.name} (${ide.marketplace})`, async () => {
      const extensionsDir = join(tempDir, ide.protocol, "extensions");

      const variables = {
        ...defaultVariables,
        protocol: ide.protocol,
        coder_app_display_name: ide.name,
        extensions: '["ms-vscode.hexeditor"]',
        extensions_dir: extensionsDir,
      };

      const state = await runTerraformApply(import.meta.dir, variables);

      // Verify the script was created
      const extensionScript = state.resources.find(
        (res) =>
          res.type === "coder_script" && res.name === "extensions-installer",
      );

      expect(extensionScript).not.toBeNull();

      const scriptContent = extensionScript?.instances[0].attributes.script;

      // Verify IDE type is correctly set
      expect(scriptContent).toContain(`IDE_TYPE="${ide.protocol}"`);

      // Verify extensions directory is set correctly
      expect(scriptContent).toContain(`EXTENSIONS_DIR="${extensionsDir}"`);

      // Verify extension ID is present
      expect(scriptContent).toContain("ms-vscode.hexeditor");

      // Verify the case statement includes the IDE protocol (Terraform substitutes the variable)
      expect(scriptContent).toContain(`case "${ide.protocol}" in`);

      // Verify that the correct case branch exists for the IDE
      if (ide.marketplace === "Microsoft") {
        expect(scriptContent).toContain(`"vscode" | "vscode-insiders"`);
      } else {
        expect(scriptContent).toContain(
          `"vscodium" | "cursor" | "windsurf" | "kiro"`,
        );
      }

      // Verify the correct marketplace URL is present
      for (const expectedUrl of ide.expectedUrls) {
        expect(scriptContent).toContain(expectedUrl);
      }
    });
  }

  // Test extension installation from URLs (airgapped scenario)
  it("should generate script for extensions from URLs with proper variable handling", async () => {
    const extensionsDir = join(tempDir, "airgapped", "extensions");

    const variables = {
      ...defaultVariables,
      extensions_urls:
        '["https://marketplace.visualstudio.com/_apis/public/gallery/vscode/ms-vscode/hexeditor/latest"]',
      extensions_dir: extensionsDir,
    };

    const state = await runTerraformApply(import.meta.dir, variables);

    const extensionScript = state.resources.find(
      (res) =>
        res.type === "coder_script" && res.name === "extensions-installer",
    );

    expect(extensionScript).not.toBeNull();

    const scriptContent = extensionScript?.instances[0].attributes.script;

    // Verify URLs variable is populated
    expect(scriptContent).toContain("EXTENSIONS_URLS=");
    expect(scriptContent).toContain("hexeditor");

    // Verify extensions variable is empty when using URLs
    expect(scriptContent).toContain('EXTENSIONS=""');

    // Verify the script calls the URL installation function
    expect(scriptContent).toContain("install_extensions_from_urls");
  });

  // Test script logic for both extension IDs and URLs handling
  it("should handle empty extensions gracefully", async () => {
    const variables = {
      ...defaultVariables,
      extensions: "[]",
      extensions_urls: "[]",
    };

    const state = await runTerraformApply(import.meta.dir, variables);

    // Script should not exist when no extensions are provided
    const extensionScript = state.resources.find(
      (res) =>
        res.type === "coder_script" && res.name === "extensions-installer",
    );

    expect(extensionScript).toBeUndefined();
  });

  // Test script template variable substitution
  it("should properly substitute template variables in script", async () => {
    const customDir = join(tempDir, "custom-template-test");
    const testExtensions = ["ms-python.python", "ms-vscode.cpptools"];

    const variables = {
      ...defaultVariables,
      protocol: "cursor",
      extensions: JSON.stringify(testExtensions),
      extensions_dir: customDir,
    };

    const state = await runTerraformApply(import.meta.dir, variables);
    const extensionScript = state.resources.find(
      (res) =>
        res.type === "coder_script" && res.name === "extensions-installer",
    )?.instances[0].attributes.script;

    // Verify all template variables are properly substituted
    expect(extensionScript).toContain(
      `EXTENSIONS="${testExtensions.join(",")}"`,
    );
    expect(extensionScript).toContain(`EXTENSIONS_URLS=""`);
    expect(extensionScript).toContain(`EXTENSIONS_DIR="${customDir}"`);
    expect(extensionScript).toContain(`IDE_TYPE="cursor"`);

    // Verify Terraform template variables are properly substituted (no double braces)
    expect(extensionScript).not.toContain("$${");

    // Verify script contains proper bash functions
    expect(extensionScript).toContain("generate_extension_url()");
    expect(extensionScript).toContain("install_extensions_from_ids");
    expect(extensionScript).toContain("install_extensions_from_urls");
  });
});
