#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const args = process.argv.slice(2);
const portIdx = args.findIndex((arg) => arg === "--port") + 1;
const port = portIdx ? args[portIdx] : 3284;

if (args.includes("--version")) {
  console.log("agentapi version 99.99.99");
  process.exit(0);
}

console.log(`starting server on port ${port}`);
fs.writeFileSync(
  "/home/coder/agentapi-mock.log",
  `AGENTAPI_ALLOWED_HOSTS: ${process.env.AGENTAPI_ALLOWED_HOSTS}`,
);

// Log state persistence env vars.
for (const v of [
  "AGENTAPI_STATE_FILE",
  "AGENTAPI_PID_FILE",
  "AGENTAPI_SAVE_STATE",
  "AGENTAPI_LOAD_STATE",
]) {
  if (process.env[v]) {
    fs.appendFileSync(
      "/home/coder/agentapi-mock.log",
      `\n${v}: ${process.env[v]}`,
    );
  }
}

// Write PID file for shutdown script.
if (process.env.AGENTAPI_PID_FILE) {
  const path = require("path");
  fs.mkdirSync(path.dirname(process.env.AGENTAPI_PID_FILE), {
    recursive: true,
  });
  fs.writeFileSync(process.env.AGENTAPI_PID_FILE, String(process.pid));
}

http
  .createServer(function (_request, response) {
    response.writeHead(200);
    response.end(
      JSON.stringify({
        status: "stable",
      }),
    );
  })
  .listen(port);
