#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const args = process.argv.slice(2);
const port = 3284;

const controlFile = "/tmp/agentapi-mock.control";
let control = "";
if (fs.existsSync(controlFile)) {
  control = fs.readFileSync(controlFile, "utf8");
}

if (
  control === "no-conversation-found" &&
  args.join(" ").includes("--continue")
) {
  // this must match the error message in the agentapi-start.sh script
  console.error("No conversation found to continue");
  process.exit(1);
}

console.log(`starting server on port ${port}`);

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
