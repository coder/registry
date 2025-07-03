#!/usr/bin/env node

const http = require("http");
const args = process.argv.slice(2);
console.log(args);
const port = 3284;

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
