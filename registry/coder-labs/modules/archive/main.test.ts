import { describe, expect, it, beforeAll } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";

const USE_XTRACE =
  process.env.ARCHIVE_TEST_XTRACE === "1" || process.env.XTRACE === "1";

const IMAGE = "alpine";
const BIN_DIR = "/tmp/coder-script-data/bin";
const DATA_DIR = "/tmp/coder-script-data";

type ExecResult = {
  exitCode: number;
  stdout: string;
  stderr: string;
};

const ensureRunOk = (label: string, res: ExecResult) => {
  if (res.exitCode !== 0) {
    console.error(
      `[${label}] non-zero exit code: ${res.exitCode}\n--- stdout ---\n${res.stdout.trim()}\n--- stderr ---\n${res.stderr.trim()}\n--------------`,
    );
  }
  expect(res.exitCode).toBe(0);
};

const sh = async (id: string, cmd: string): Promise<ExecResult> => {
  const res = await execContainer(id, ["sh", "-c", cmd]);
  return res;
};

const bashRun = async (id: string, cmd: string): Promise<ExecResult> => {
  const injected = USE_XTRACE ? `/bin/bash -x ${cmd}` : cmd;
  return sh(id, injected);
};

const prepareContainer = async (image = IMAGE) => {
  const id = await runContainer(image);
  // Prepare script dirs and deps.
  ensureRunOk(
    "mkdirs",
    await sh(id, `mkdir -p ${BIN_DIR} ${DATA_DIR} /tmp/backup`),
  );

  // Install tools used by tests.
  ensureRunOk(
    "apk add",
    await sh(id, "apk add --no-cache bash tar gzip zstd coreutils"),
  );

  return id;
};

const installArchive = async (
  state: TerraformState,
  opts?: { env?: string[] },
) => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await prepareContainer();
  // Run installer script with correct env for CODER_SCRIPT paths.
  const args = ["bash"];
  if (USE_XTRACE) args.push("-x");
  args.push("-c", instance.script);

  const resp = await execContainer(id, args, [
    "--env",
    `CODER_SCRIPT_BIN_DIR=${BIN_DIR}`,
    "--env",
    `CODER_SCRIPT_DATA_DIR=${DATA_DIR}`,
    ...(opts?.env ?? []),
  ]);

  return {
    id,
    install: {
      exitCode: resp.exitCode,
      stdout: resp.stdout.trim(),
      stderr: resp.stderr.trim(),
    },
  };
};

const fileExists = async (id: string, path: string) => {
  const res = await sh(id, `test -f ${path} && echo yes || echo no`);
  return res.stdout.trim() === "yes";
};

const isExecutable = async (id: string, path: string) => {
  const res = await sh(id, `test -x ${path} && echo yes || echo no`);
  return res.stdout.trim() === "yes";
};

const listTar = async (id: string, path: string) => {
  // Try to autodetect compression flags from extension.
  let cmd = "";
  if (path.endsWith(".tar.gz")) {
    cmd = `tar -tzf ${path}`;
  } else if (path.endsWith(".tar.zst")) {
    // validate with zstd and ask tar to list via --zstd.
    cmd = `zstd -t -q ${path} && tar --zstd -tf ${path}`;
  } else {
    cmd = `tar -tf ${path}`;
  }
  return sh(id, cmd);
};

describe("archive", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  // Ensure required variables are enforced.
  testRequiredVariables(import.meta.dir, {
    agent_id: "agent-123",
  });

  it("installs wrapper scripts to BIN_DIR and library to DATA_DIR", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
    });

    // The Terraform output should reflect defaults from main.tf.
    expect(state.outputs.archive_path.value).toEqual(
      "/tmp/coder-archive.tar.gz",
    );

    const { id, install } = await installArchive(state);
    ensureRunOk("install", install);

    expect(install.stdout).toContain(
      `Installed archive library to: ${DATA_DIR}/archive-lib.sh`,
    );
    expect(install.stdout).toContain(
      `Installed create script to:   ${BIN_DIR}/coder-archive-create`,
    );
    expect(install.stdout).toContain(
      `Installed extract script to:  ${BIN_DIR}/coder-archive-extract`,
    );
    expect(await isExecutable(id, `${BIN_DIR}/coder-archive-create`)).toBe(
      true,
    );
    expect(await isExecutable(id, `${BIN_DIR}/coder-archive-extract`)).toBe(
      true,
    );
  });

  it("uses sane defaults: creates gzip archive at the default path and logs to stderr", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      // Keep defaults: compression=gzip, output_dir=/tmp, archive_name=coder-archive.
    });

    const { id } = await installArchive(state);

    const createTestdata = await bashRun(
      id,
      `mkdir ~/gzip; touch ~/gzip/defaults.txt`,
    );
    ensureRunOk("create testdata", createTestdata);

    const run = await bashRun(id, `${BIN_DIR}/coder-archive-create`);
    ensureRunOk("archive-create default run", run);

    // Only the archive path should print to stdout.
    expect(run.stdout.trim()).toEqual("/tmp/coder-archive.tar.gz");
    expect(await fileExists(id, "/tmp/coder-archive.tar.gz")).toBe(true);

    // Some useful diagnostics should be on stderr.
    expect(run.stderr).toContain("Creating archive:");
    expect(run.stderr).toContain("Compression: gzip");

    const list = await listTar(id, "/tmp/coder-archive.tar.gz");
    ensureRunOk("list default archive", list);
    expect(list.stdout).toContain("gzip/defaults.txt");
  }, 20000);

  it("creates a gzip archive with explicit -f and includes extra CLI paths", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      // Provide a simple default path so we can assert contents.
      paths: `["~/gzip"]`,
      compression: "gzip",
    });

    const { id } = await installArchive(state);

    const createTestdata = await bashRun(
      id,
      `mkdir ~/gzip; touch ~/gzip/test.txt; touch ~/gziptest.txt`,
    );
    ensureRunOk("create testdata", createTestdata);

    const out = "/tmp/backup/test-archive.tar.gz";
    const run = await bashRun(
      id,
      `${BIN_DIR}/coder-archive-create -f ${out} ~/gziptest.txt`,
    );
    ensureRunOk("archive-create gzip explicit -f", run);

    expect(run.stdout.trim()).toEqual(out);
    expect(await fileExists(id, out)).toBe(true);

    const list = await sh(id, `tar -tzf ${out}`);
    ensureRunOk("tar -tzf contents (gzip)", list);
    expect(list.stdout).toContain("gzip/test.txt");
    expect(list.stdout).toContain("gziptest.txt");
  }, 20000);

  it("creates a zstd-compressed archive when requested via CLI override", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      paths: `["/etc/hostname"]`,
      // Module default is gzip, override at runtime to zstd.
    });

    const { id } = await installArchive(state);

    const out = "/tmp/backup/zstd-archive.tar.zst";
    const run = await bashRun(
      id,
      `${BIN_DIR}/coder-archive-create --compression zstd -f ${out}`,
    );
    ensureRunOk("archive-create zstd", run);

    expect(run.stdout.trim()).toEqual(out);

    // Check integrity via zstd and that tar can list it.
    ensureRunOk("zstd -t", await sh(id, `test -f ${out} && zstd -t -q ${out}`));
    ensureRunOk("tar --zstd -tf", await sh(id, `tar --zstd -tf ${out}`));
  }, 30000);

  it("creates an uncompressed tar when compression=none", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      // Keep module defaults but override at runtime.
    });

    const { id } = await installArchive(state);

    const out = "/tmp/backup/raw-archive.tar";
    const run = await bashRun(
      id,
      `${BIN_DIR}/coder-archive-create --compression none -f ${out}`,
    );
    ensureRunOk("archive-create none", run);

    expect(run.stdout.trim()).toEqual(out);
    ensureRunOk("tar -tf (none)", await sh(id, `tar -tf ${out} >/dev/null`));
  }, 20000);

  it("applies exclude patterns from Terraform", async () => {
    // Include a file, but also exclude it via Terraform defaults to ensure
    // exclusion flows through.
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      paths: `["/etc/hostname"]`,
      exclude_patterns: `["/etc/hostname"]`,
    });

    const { id } = await installArchive(state);

    const out = "/tmp/backup/excluded.tar.gz";
    const run = await bashRun(id, `${BIN_DIR}/coder-archive-create -f ${out}`);
    ensureRunOk("archive-create with exclude_patterns", run);

    const list = await sh(id, `tar -tzf ${out}`);
    ensureRunOk("tar -tzf contents (exclude)", list);
    expect(list.stdout).not.toContain("etc/hostname"); // Excluded by Terraform default.
  }, 20000);

  it("adds a run_on_stop script when enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      create_on_stop: true,
    });

    const coderScripts = state.resources.filter(
      (r) => r.type === "coder_script",
    );
    // Installer (run_on_start) + run_on_stop.
    expect(coderScripts.length).toBe(2);
  });

  it("extracts a previously created archive into a target directory", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      paths: `["/etc/hostname"]`,
      compression: "gzip",
    });

    const { id } = await installArchive(state);

    // Create archive.
    const out = "/tmp/backup/extract-test.tar.gz";
    const created = await bashRun(
      id,
      `${BIN_DIR}/coder-archive-create -f ${out} /etc/hosts`,
    );
    ensureRunOk("create for extract", created);

    // Extract archive.
    const extractDir = "/tmp/extract";
    const extract = await bashRun(
      id,
      `${BIN_DIR}/coder-archive-extract -f ${out} -C ${extractDir}`,
    );
    ensureRunOk("archive-extract", extract);

    // Verify a known file exists after extraction.
    const exists = await sh(
      id,
      `test -f ${extractDir}/etc/hosts && echo ok || echo no`,
    );
    expect(exists.stdout.trim()).toEqual("ok");
  }, 20000);

  it("honors Terraform defaults without CLI args (compression, name, output_dir)", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "agent-123",
      compression: "zstd",
      archive_name: "my-default",
      output_dir: "/tmp/defout",
    });

    const { id } = await installArchive(state);

    const run = await bashRun(id, `${BIN_DIR}/coder-archive-create`);
    ensureRunOk("archive-create terraform defaults", run);
    expect(run.stdout.trim()).toEqual("/tmp/defout/my-default.tar.zst");
    expect(run.stderr).toContain("Creating archive:");
    expect(run.stderr).toContain("Compression: zstd");
    ensureRunOk(
      "zstd -t",
      await sh(id, "zstd -t -q /tmp/defout/my-default.tar.zst"),
    );
    ensureRunOk(
      "tar --zstd -tf",
      await sh(id, "tar --zstd -tf /tmp/defout/my-default.tar.zst"),
    );
  }, 30000);
});
