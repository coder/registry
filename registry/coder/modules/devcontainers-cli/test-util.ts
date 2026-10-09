import { expect } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  writeFileContainer,
  type scriptOutput,
  type TerraformState,
} from "~test";

export const SCRIPT_DATA_DIR = "/tmp/coder-script-data";
export const SCRIPT_BIN_DIR = `${SCRIPT_DATA_DIR}/bin`;

type ContainerSetup = (containerID: string) => Promise<void>;

type AlpineScriptOutput = scriptOutput & {
  packageManagerArgs: string[];
};

export const writeExecutable = async (
  containerID: string,
  path: string,
  content: string,
): Promise<void> => {
  await writeFileContainer(containerID, path, content, { user: "root" });
  const result = await execContainer(
    containerID,
    ["chmod", "755", path],
    ["--user", "root"],
  );
  expect(result.exitCode).toBe(0);
};

export const packageManagerStub = (
  exitCode = 0,
  createDevcontainer = true,
): string => `#!/bin/sh
printf '%s\\n' "$@" > /tmp/package-manager-args
${
  createDevcontainer
    ? `mkdir -p "$CODER_SCRIPT_BIN_DIR"
printf '#!/bin/sh\\nexit 0\\n' > "$CODER_SCRIPT_BIN_DIR/devcontainer"
chmod +x "$CODER_SCRIPT_BIN_DIR/devcontainer"`
    : ""
}
exit ${exitCode}
`;

export const executeInAlpine = async (
  state: TerraformState,
  setup: ContainerSetup,
): Promise<AlpineScriptOutput> => {
  const instance = findResourceInstance(state, "coder_script");
  const containerID = await runContainer("alpine");

  try {
    await execContainer(containerID, ["mkdir", "-p", SCRIPT_BIN_DIR]);
    await setup(containerID);

    const path = `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${SCRIPT_BIN_DIR}`;
    const env = [
      "--env",
      `CODER_SCRIPT_DATA_DIR=${SCRIPT_DATA_DIR}`,
      "--env",
      `PATH=${path}`,
      "--env",
      `CODER_SCRIPT_BIN_DIR=${SCRIPT_BIN_DIR}`,
    ];
    const response = await execContainer(
      containerID,
      ["sh", "-c", instance.script],
      env,
    );
    const argsResponse = await execContainer(containerID, [
      "sh",
      "-c",
      "if [ -f /tmp/package-manager-args ]; then cat /tmp/package-manager-args; fi",
    ]);
    return {
      exitCode: response.exitCode,
      stdout: response.stdout.trim() ? response.stdout.trim().split("\n") : [],
      stderr: response.stderr.trim() ? response.stderr.trim().split("\n") : [],
      packageManagerArgs: argsResponse.stdout.trim()
        ? argsResponse.stdout.trim().split("\n")
        : [],
    };
  } finally {
    await removeContainer(containerID);
  }
};

export const setupPackageManager = async (
  containerID: string,
  packageManager: "npm" | "pnpm" | "yarn",
  stub = packageManagerStub(),
): Promise<void> => {
  await writeExecutable(
    containerID,
    "/usr/local/bin/docker",
    "#!/bin/sh\nexit 0\n",
  );
  await writeExecutable(containerID, `/usr/local/bin/${packageManager}`, stub);
};
