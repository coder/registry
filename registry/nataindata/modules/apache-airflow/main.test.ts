import {
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
} from "bun:test";
import {
  chmodSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runTerraformInit } from "~test";

let installScript: string;
let startScript: string;
let testDirectory: string;
let bin: string;
let trace: string;

function renderScript(
  name: string,
  variables: Record<string, string> = {},
): string {
  const result = Bun.spawnSync(
    [
      "terraform",
      "console",
      "-var=agent_id=test-agent",
      ...Object.entries(variables).map(
        ([key, value]) => `-var=${key}=${value}`,
      ),
    ],
    {
      cwd: import.meta.dir,
      stdin: Buffer.from(`base64encode(local.${name}_script)\n`),
    },
  );
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
  return Buffer.from(JSON.parse(result.stdout.toString()), "base64").toString();
}

function executable(name: string, contents: string): void {
  const path = join(bin, name);
  writeFileSync(path, `#!/usr/bin/env bash\n${contents}\n`);
  chmodSync(path, 0o755);
}

function run(script: string, environment: Record<string, string> = {}) {
  return Bun.spawnSync(["/bin/bash", "-c", script], {
    env: {
      HOME: testDirectory,
      PATH: bin,
      TRACE: trace,
      ...environment,
    },
  });
}

function installer(name: string, exitCode = 0): void {
  executable(
    name,
    `printf '${name}'; printf '<%s>' "$@" >> "$TRACE"; exit ${exitCode}`,
  );
}

function airflow(): void {
  executable(
    "airflow",
    `
printf '<%s>' "$@" >> "$TRACE"
printf '\\n' >> "$TRACE"
if [ "$1 $2" = "\${FAIL_COMMAND:-}" ]; then exit 42; fi
if [ "$1 $2" = "users list" ]; then printf '%s\\n' "\${USERS:-[]}"; fi
`,
  );
}

beforeAll(async () => {
  await runTerraformInit(import.meta.dir);
  installScript = renderScript("install");
  startScript = renderScript("start");
}, 120_000);

beforeEach(() => {
  testDirectory = mkdtempSync(join(tmpdir(), "airflow-test-"));
  bin = join(testDirectory, "bin");
  trace = join(testDirectory, "trace");
  mkdirSync(bin);
  writeFileSync(trace, "");
  for (const name of ["bash", "base64", "dirname", "mkdir", "python3"]) {
    const command = Bun.which(name);
    if (!command) throw new Error(`Required test command not found: ${name}`);
    symlinkSync(command, join(bin, name));
  }
});

afterEach(() => rmSync(testDirectory, { recursive: true, force: true }));

describe("isolated Airflow installation", () => {
  it("prefers uv and passes the same Python to the constraints and environment", () => {
    installer("uv");
    installer("pipx", 99);
    const result = run(installScript);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("uv");
    const args = readFileSync(trace, "utf8");
    expect(args).toContain("<tool><install><--upgrade><--python>");
    expect(args).toContain(`<${bin}/python3>`);
    expect(args).toContain("constraints-2.11.0/constraints-");
    expect(args).toContain("<apache-airflow==2.11.0>");
  });

  it("uses pipx only when uv is absent", () => {
    installer("pipx");
    const result = run(installScript);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("pipx");
    expect(readFileSync(trace, "utf8")).toContain(
      "<install><--force><--python>",
    );
    expect(readFileSync(trace, "utf8")).toContain(
      "<--pip-args=--constraint https://",
    );
  });

  it("reports missing installers", () => {
    const result = run(installScript);
    expect(result.exitCode).toBe(1);
    expect(result.stderr.toString()).toContain("Airflow requires uv or pipx");
  });

  for (const tool of ["uv", "pipx"]) {
    it(`propagates ${tool} installation failures`, () => {
      installer(tool, 42);
      if (tool === "uv") installer("pipx", 99);
      expect(run(installScript).exitCode).toBe(42);
    });
  }

  it("finds an installer in the user's local bin", () => {
    const localBin = join(testDirectory, ".local/bin");
    mkdirSync(localBin, { recursive: true });
    executable("uv", "exit 99");
    writeFileSync(join(localBin, "uv"), "#!/usr/bin/env bash\nexit 0\n", {
      mode: 0o755,
    });
    expect(run(installScript).exitCode).toBe(0);
  });
});

describe("Airflow startup", () => {
  beforeEach(airflow);

  it("migrates the database and creates the initial admin before starting services", () => {
    expect(run(startScript).exitCode).toBe(0);
    const calls = readFileSync(trace, "utf8");
    expect(calls).toContain("<db><migrate>");
    expect(calls).toContain("<users><create><-u><admin>");
    expect(calls).toContain("<webserver><--port><8080><--daemon>");
    expect(calls).toContain(
      `${testDirectory}/.coder-modules/nataindata/apache-airflow/logs/webserver.log`,
    );
    expect(calls.indexOf("<users><create>")).toBeLessThan(
      calls.indexOf("<webserver>"),
    );
    expect(calls).toContain("<scheduler><--daemon>");
  });

  it("preserves an existing admin on restart", () => {
    expect(run(startScript, { USERS: '[{"username":"admin"}]' }).exitCode).toBe(
      0,
    );
    expect(readFileSync(trace, "utf8")).not.toContain("<users><create>");
  });

  it("preserves custom ports and literal log paths with shell metacharacters", () => {
    const logPath = join(
      testDirectory,
      "airflow's $(touch injected) logs/output.log",
    );
    const script = renderScript("start", { port: "9090", log_path: logPath });
    expect(run(script).exitCode).toBe(0);
    expect(readFileSync(trace, "utf8")).toContain("<webserver><--port><9090>");
    expect(readFileSync(trace, "utf8")).toContain(`<--stdout><${logPath}>`);
  });

  for (const command of ["db migrate", "users list", "users create"]) {
    it(`stops on ${command} failure`, () => {
      expect(run(startScript, { FAIL_COMMAND: command }).exitCode).toBe(42);
      expect(readFileSync(trace, "utf8")).not.toContain("<webserver>");
    });
  }

  it("does not mistake malformed user data for a missing admin", () => {
    expect(run(startScript, { USERS: "invalid json" }).exitCode).not.toBe(0);
    expect(readFileSync(trace, "utf8")).not.toContain("<users><create>");
    expect(readFileSync(trace, "utf8")).not.toContain("<webserver>");
  });

  for (const command of ["webserver --port", "scheduler --daemon"]) {
    it(`propagates ${command} failure`, () => {
      expect(run(startScript, { FAIL_COMMAND: command }).exitCode).toBe(42);
      if (command.startsWith("webserver")) {
        expect(readFileSync(trace, "utf8")).not.toContain("<scheduler>");
      }
    });
  }
});
