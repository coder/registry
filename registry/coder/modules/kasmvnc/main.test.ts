import { describe, expect, it } from "bun:test";
import { readableStreamToText, spawn } from "bun";
import { readFile } from "node:fs/promises";
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

type Platform = Readonly<{
  distro: string;
  codename?: string;
  distroVersion?: string;
  arch: string;
  fedoraCodename?: string;
}>;

type PackageNameCase = Readonly<{
  label: string;
  platform: Platform;
  version: string;
  expected: string;
}>;

/**
 * Extracts a block from run.sh, which is a Terraform template: `$${VAR}`
 * escapes a shell expansion, and `${VAR}` is substituted at plan time. Failing
 * loudly here is intentional, so a refactor of run.sh cannot silently stop
 * these assertions from covering the naming logic.
 */
const extractFromRunScript = (
  source: string,
  pattern: RegExp,
  optional = false,
): string => {
  const match = source.match(pattern);
  if (!match) {
    if (optional) {
      return "";
    }
    throw new Error(
      `Could not find ${pattern} in run.sh. Update this test if run.sh was restructured.`,
    );
  }
  return match[0];
};

/**
 * Runs the release package naming block from run.sh for the given platform and
 * version, and returns the asset name it would download. The install functions
 * are stubbed, so nothing is downloaded and nothing is installed.
 */
const packageNameFor = async (
  platform: Platform,
  version: string,
): Promise<{ name: string; exitCode: number; stderr: string }> => {
  const source = (
    await readFile(`${import.meta.dir}/run.sh`, "utf8")
  ).replaceAll("$${", "${");
  const harness = [
    "set -euo pipefail",
    'error() { printf "%s\\n" "$*" >&2; exit 1; }',
    extractFromRunScript(
      source,
      /^version_ge\(\) \{[\s\S]*?^\}$/m,
      // Older revisions of run.sh had no comparator at all; the naming block
      // still runs, so the assertions report the names it would have used.
      true,
    ),
    'install_deb() { echo "${1##*/}"; }',
    'install_rpm() { echo "${1##*/}"; }',
    'install_apk() { echo "${1##*/}"; }',
    'install_alpine() { echo "${1##*/}"; }',
    `base_url="https://example.invalid/v${version}"`,
    extractFromRunScript(source, /^ {2}case \$distro in\n[\s\S]*?^ {2}esac$/m),
  ].join("\n");

  const proc = spawn(["bash", "-c", harness], {
    env: {
      ...process.env,
      distro: platform.distro,
      codename: platform.codename ?? "",
      distro_version: platform.distroVersion ?? "",
      arch: platform.arch,
      KASM_VERSION: version,
      fedora_codename: platform.fedoraCodename ?? "",
    },
    stderr: "pipe",
    stdout: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    readableStreamToText(proc.stdout),
    readableStreamToText(proc.stderr),
  ]);
  return { name: stdout.trim(), exitCode: await proc.exited, stderr };
};

// KasmVNC has renamed its release assets twice since this module was written:
// the distro prefix was added to deb assets in 1.5.1, Fedora switched from
// release names (fedora_forty) to major versions (fedora_42) in 1.5.0, and
// Alpine replaced its tarball with an apk package in 1.4.0. Every row below is
// a name that exists on the releases page, so a failure here means a workspace
// would 404 while installing.
const packageNameCases: ReadonlyArray<PackageNameCase> = [
  {
    label: "ubuntu deb before the 1.5.1 rename",
    platform: {
      distro: "ubuntu",
      codename: "noble",
      distroVersion: "24.04",
      arch: "amd64",
    },
    version: "1.5.0",
    expected: "kasmvncserver_noble_1.5.0_amd64.deb",
  },
  {
    label: "ubuntu deb after the 1.5.1 rename",
    platform: {
      distro: "ubuntu",
      codename: "noble",
      distroVersion: "24.04",
      arch: "amd64",
    },
    version: "1.5.1",
    expected: "kasmvncserver_ubuntu_noble_1.5.1_amd64.deb",
  },
  {
    label: "debian deb on arm64",
    platform: {
      distro: "debian",
      codename: "bookworm",
      distroVersion: "12",
      arch: "arm64",
    },
    version: "1.5.2",
    expected: "kasmvncserver_debian_bookworm_1.5.2_arm64.deb",
  },
  {
    label: "kali deb keeps the distro in its codename",
    platform: {
      distro: "kali",
      codename: "kali-rolling",
      distroVersion: "2025.1",
      arch: "amd64",
    },
    version: "1.5.2",
    expected: "kasmvncserver_kali_kali-rolling_1.5.2_amd64.deb",
  },
  {
    label: "oracle rpm uses the major version",
    platform: { distro: "oracle", distroVersion: "8.9", arch: "x86_64" },
    version: "1.5.2",
    expected: "kasmvncserver_oracle_8_1.5.2_x86_64.rpm",
  },
  {
    label: "opensuse leap rpm uses the major version",
    platform: { distro: "opensuse", distroVersion: "15.6", arch: "x86_64" },
    version: "1.5.2",
    expected: "kasmvncserver_opensuse_15_1.5.2_x86_64.rpm",
  },
  {
    label: "fedora rpm before 1.5.0 uses the release name",
    platform: {
      distro: "fedora",
      distroVersion: "40",
      arch: "x86_64",
      fedoraCodename: "forty",
    },
    version: "1.4.0",
    expected: "kasmvncserver_fedora_forty_1.4.0_x86_64.rpm",
  },
  {
    label: "fedora rpm from 1.5.0 uses the major version",
    platform: {
      distro: "fedora",
      distroVersion: "42",
      arch: "x86_64",
      fedoraCodename: "fortytwo",
    },
    version: "1.5.0",
    expected: "kasmvncserver_fedora_42_1.5.0_x86_64.rpm",
  },
  {
    label: "alpine tarball before 1.4.0",
    platform: { distro: "alpine", distroVersion: "3.21.0", arch: "x86_64" },
    version: "1.3.2",
    expected: "kasmvnc.alpine_321_x86_64.tgz",
  },
  {
    label: "alpine apk from 1.4.0",
    platform: { distro: "alpine", distroVersion: "3.21.0", arch: "x86_64" },
    version: "1.4.0",
    expected: "kasmvncserver_alpine_321_1.4.0_x86_64.apk",
  },
  {
    label: "alpine apk on 3.22 arm64",
    platform: { distro: "alpine", distroVersion: "3.22.1", arch: "aarch64" },
    version: "1.5.2",
    expected: "kasmvncserver_alpine_322_1.5.2_aarch64.apk",
  },
];

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

  describe("release package name", () => {
    for (const testCase of packageNameCases) {
      it(testCase.label, async () => {
        const result = await packageNameFor(
          testCase.platform,
          testCase.version,
        );

        expect(result.name).toBe(testCase.expected);
      });
    }

    it("rejects a kasm_version that is not X.Y.Z", async () => {
      const result = await packageNameFor(
        {
          distro: "ubuntu",
          codename: "noble",
          distroVersion: "24.04",
          arch: "amd64",
        },
        "1.5",
      );

      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("Unsupported kasm_version");
    });
  });
});
