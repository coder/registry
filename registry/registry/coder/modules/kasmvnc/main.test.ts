import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const allowedDesktopEnvs = ["xfce", "kde", "gnome", "lxde", "lxqt"] as const;
type AllowedDesktopEnv = (typeof allowedDesktopEnvs)[number];

type TestVariables = Readonly<{
  agent_id: string;
  desktop_environment: AllowedDesktopEnv;
  port?: string;
  kasm_version?: string;
}>;

describe("Kasm VNC", async () => {
  await runTerraformInit(import.meta.dir);
  testRequiredVariables<TestVariables>(import.meta.dir, {
    agent_id: "foo",
    desktop_environment: "gnome",
  });

  it("Successfully installs for all expected Kasm desktop versions", async () => {
    for (const v of allowedDesktopEnvs) {
      const applyWithEnv = () => {
        runTerraformApply<TestVariables>(import.meta.dir, {
          agent_id: "foo",
          desktop_environment: v,
        });
      };

      expect(applyWithEnv).not.toThrow();
    }
  });
});
