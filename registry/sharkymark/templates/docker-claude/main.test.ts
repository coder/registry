import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const template = readFileSync(`${import.meta.dir}/main.tf`, "utf8");
const packages = template.match(
  /# Packages: Install additional packages\n([\s\S]*?)\n\s*# MCP:/,
)?.[1];
if (!packages) throw new Error("Default preset package installation not found");

function installPackages(updateStatus: number, installStatus: number) {
  return spawnSync(
    "bash",
    [
      "-c",
      `
      sudo() { "$@"; }
      apt-get() {
        echo "apt-get $*"
        if [ "$1" = update ]; then
          if [ "$UPDATE_STATUS" != 0 ]; then
            echo "E: The Yarn repository is not signed." >&2
          fi
          return "$UPDATE_STATUS"
        fi
        return "$INSTALL_STATUS"
      }
      google-chrome() { :; }
      ${packages}
      echo "Continuing setup"
      `,
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        UPDATE_STATUS: String(updateStatus),
        INSTALL_STATUS: String(installStatus),
      },
    },
  );
}

describe("default preset tmux installation", () => {
  for (const updateStatus of [0, 100]) {
    test(`installs tmux when apt-get update exits ${updateStatus}`, () => {
      const result = installPackages(updateStatus, 0);
      expect(result.status).toBe(0);
      expect(result.stdout).toContain("apt-get install -y tmux");
      expect(result.stdout).toContain("Continuing setup");
      if (updateStatus !== 0) {
        expect(result.stderr).toContain(
          "E: The Yarn repository is not signed.",
        );
        expect(result.stderr).toContain("Warning:");
      }
    });

    test(`stops on install failure when apt-get update exits ${updateStatus}`, () => {
      const result = installPackages(updateStatus, 100);
      expect(result.status).toBe(100);
      expect(result.stdout).toContain("apt-get install -y tmux");
      expect(result.stdout).not.toContain("Continuing setup");
    });
  }
});
