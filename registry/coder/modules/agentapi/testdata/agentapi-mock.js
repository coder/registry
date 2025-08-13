#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const args = process.argv.slice(2);
const portIdx = args.findIndex((arg) => arg === "--port") + 1;
const port = portIdx ? args[portIdx] : 3284;

console.log(`starting server on port ${port}`);
fs.writeFileSync("/home/coder/agentapi-mock.log", `AGENTAPI_ALLOWED_HOSTS: ${process.env.AGENTAPI_ALLOWED_HOSTS}`);

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
