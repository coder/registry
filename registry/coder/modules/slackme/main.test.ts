import { serve } from "bun";
import { describe, expect, it } from "bun:test";
import {
  createJSONResponse,
  execContainer,
  findResourceInstance,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeCoder,
} from "~test";

describe("slackme", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    auth_provider_id: "foo",
  });

  it("writes to path as executable", async () => {
    const { instance, id } = await setupContainer();
    await writeCoder(id, "exit 0");
    let exec = await execContainer(id, ["sh", "-c", instance.script]);
    expect(exec.exitCode).toBe(0);
    exec = await execContainer(id, ["sh", "-c", "which slackme"]);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout.trim()).toEqual("/usr/bin/slackme");
  });

  it("prints usage with no command", async () => {
    const { instance, id } = await setupContainer();
    await writeCoder(id, "echo 👋");
    let exec = await execContainer(id, ["sh", "-c", instance.script]);
    expect(exec.exitCode).toBe(0);
    exec = await execContainer(id, ["sh", "-c", "slackme"]);
    expect(exec.stdout.trim()).toStartWith(
      "slackme — Send a Slack notification when a command finishes",
    );
  });

  it("displays url when not authenticated", async () => {
    const { instance, id } = await setupContainer();
    await writeCoder(id, "echo 'some-url' && exit 1");
    let exec = await execContainer(id, ["sh", "-c", instance.script]);
    expect(exec.exitCode).toBe(0);
    exec = await execContainer(id, ["sh", "-c", "slackme echo test"]);
    expect(exec.stdout.trim()).toEndWith("some-url");
  });

  it("default output", async () => {
    await assertSlackMessage({
      command: "echo test",
      durationMS: 2,
      output: "👨‍💻 `echo test` completed in 2ms",
    });
  });

  it("formats multiline message", async () => {
    await assertSlackMessage({
      command: "echo test",
      format: `this command:
\`$COMMAND\`
executed`,
      output: `this command:
\`echo test\`
executed`,
    });
  });

  it("formats execution with milliseconds", async () => {
    await assertSlackMessage({
      command: "echo test",
      format: "$COMMAND took $DURATION",
      durationMS: 150,
      output: "echo test took 150ms",
    });
  });

  it("formats execution with seconds", async () => {
    await assertSlackMessage({
      command: "echo test",
      format: "$COMMAND took $DURATION",
      durationMS: 15000,
      output: "echo test took 15.0s",
    });
  });

  it("formats execution with minutes", async () => {
    await assertSlackMessage({
      command: "echo test",
      format: "$COMMAND took $DURATION",
      durationMS: 120000,
      output: "echo test took 2m 0.0s",
    });
  });

  it("formats execution with hours", async () => {
    await assertSlackMessage({
      command: "echo test",
      format: "$COMMAND took $DURATION",
      durationMS: 60000 * 60,
      output: "echo test took 1hr 0m 0.0s",
    });
  });
});

const setupContainer = async (
  image = "alpine",
  vars: Record<string, string> = {},
) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    auth_provider_id: "foo",
    ...vars,
  });
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);
  return { id, instance };
};

const assertSlackMessage = async (opts: {
  command: string;
  format?: string;
  durationMS?: number;
  output: string;
}) => {
  // Have to use non-null assertion because TS can't tell when the fetch
  // function will run
  let url!: URL;

  const fakeSlackHost = serve({
    fetch: (req) => {
      url = new URL(req.url);
      if (url.pathname === "/api/chat.postMessage")
        return createJSONResponse({
          ok: true,
        });
      return createJSONResponse({}, 404);
    },
    port: 0,
  });

  const { instance, id } = await setupContainer(
    "alpine/curl",
    opts.format ? { slack_message: opts.format } : undefined,
  );

  await writeCoder(id, "echo 'token'");
  let exec = await execContainer(id, ["sh", "-c", instance.script]);
  expect(exec.exitCode).toBe(0);

  exec = await execContainer(id, [
    "sh",
    "-c",
    `DURATION_MS=${opts.durationMS || 0} SLACK_URL="http://${
      fakeSlackHost.hostname
    }:${fakeSlackHost.port}" slackme ${opts.command}`,
  ]);

  expect(exec.stderr.trim()).toBe("");
  expect(url.pathname).toEqual("/api/chat.postMessage");
  expect(url.searchParams.get("channel")).toEqual("token");
  expect(url.searchParams.get("text")).toEqual(opts.output);
};
