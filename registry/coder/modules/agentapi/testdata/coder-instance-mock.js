#!/usr/bin/env node
// Mock Coder instance server for shutdown script tests.
// Captures POST requests to /log-snapshot endpoint.

const http = require("http");
const fs = require("fs");
const port = process.argv[2] || 8080;
const outputFile = process.env.OUTPUT_FILE || "/tmp/snapshot-posted.json";
const httpCode = parseInt(process.env.HTTP_CODE || "204", 10);

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);

  // Expected path: /api/v2/workspaceagents/me/tasks/{task_id}/log-snapshot
  const pathMatch = url.pathname.match(/\/tasks\/([^\/]+)\/log-snapshot$/);

  if (req.method === "POST" && pathMatch) {
    const taskId = pathMatch[1];
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", () => {
      // Save captured snapshot with task ID for verification
      const snapshotData = {
        task_id: taskId,
        payload: JSON.parse(body),
      };
      fs.writeFileSync(outputFile, JSON.stringify(snapshotData, null, 2));
      console.error(
        `Captured snapshot for task ${taskId} (${body.length} bytes) to ${outputFile}`,
      );

      // Return configured status code
      res.writeHead(httpCode);
      res.end();
    });

    req.on("error", (err) => {
      console.error("Request error:", err);
      res.writeHead(500);
      res.end();
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(port, () => {
  console.error(`Mock Coder instance listening on port ${port}`);
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});

process.on("SIGINT", () => {
  server.close(() => process.exit(0));
});
