import { readableStreamToText, spawn } from "bun";
import { afterAll } from "bun:test";

async function removeStatefiles(): Promise<void> {
  const process = spawn([
    "find",
    ".",
    "-type",
    "f",
    "-o",
    "-name",
    "*.tfstate",
    "-o",
    "-name",
    "*.tfstate.lock.info",
    "-delete",
  ]);
  await process.exited;
}

async function removeOldContainers(): Promise<void> {
  let process = spawn([
    "docker",
    "ps",
    "-a",
    "-q",
    "--filter",
    "label=modules-test",
  ]);
  let containerIDsRaw = await readableStreamToText(process.stdout);
  let exitCode = await process.exited;
  if (exitCode !== 0) {
    throw new Error(containerIDsRaw);
  }
  containerIDsRaw = containerIDsRaw.trim();
  if (containerIDsRaw === "") {
    return;
  }
  process = spawn(["docker", "rm", "-f", ...containerIDsRaw.split("\n")]);
  const stdout = await readableStreamToText(process.stdout);
  exitCode = await process.exited;
  if (exitCode !== 0) {
    throw new Error(stdout);
  }
}

afterAll(async () => {
  await Promise.all([removeStatefiles(), removeOldContainers()]);
});
