import { beforeAll, describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";

const required = {
  agent_id: "test-agent",
  command: "gimp",
  slug: "gimp",
};

// coder-utils wraps each script in base64.
const decodeScript = (state: TerraformState, name: string): string => {
  const resource = state.resources.find(
    (r) => r.type === "coder_script" && r.name === name,
  );
  expect(resource).toBeDefined();
  const wrapper = resource!.instances[0].attributes.script as string;
  const match = wrapper.match(/echo -n '([A-Za-z0-9+/=]+)'/);
  expect(match).toBeTruthy();
  return Buffer.from(match![1], "base64").toString("utf-8");
};

describe("xpra", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, required);

  it("creates a subdomain app", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      ...required,
      port: 14600,
    });
    const app = findResourceInstance(state, "coder_app");
    expect(app.slug).toBe("gimp");
    expect(app.url).toBe("http://localhost:14600/?floating_menu=false");
    expect(app.subdomain).toBe(true);
    expect(app.open_in).toBe("slim-window");
  });

  it("renders install and start scripts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      ...required,
      install_openbox: false,
    });
    const install = decodeScript(state, "install_script");
    expect(install).toContain("ARG_INSTALL_XPRA='true'");
    expect(install).toContain("ARG_INSTALL_OPENBOX='false'");

    const start = decodeScript(state, "start_script");
    expect(start).toContain("xpra desktop");
    expect(start).toContain(Buffer.from("gimp").toString("base64"));
    expect(start).toContain("$HOME/.coder-modules/phorcys/xpra-gimp");
  });
});
