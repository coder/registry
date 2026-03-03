#!/usr/bin/env node
// Mock AgentAPI server for shutdown script tests.
// Usage: MESSAGES='[...]' node agentapi-mock-shutdown.js [port]

const http = require("http");
const fs = require("fs");
const port = process.argv[2] || 3284;

// Write PID file for shutdown script.
if (process.env.AGENTAPI_PID_FILE) {
  const path = require("path");
  fs.mkdirSync(path.dirname(process.env.AGENTAPI_PID_FILE), {
    recursive: true,
  });
  fs.writeFileSync(process.env.AGENTAPI_PID_FILE, String(process.pid));
}

// Handle SIGUSR1 (state save signal from shutdown script).
process.on("SIGUSR1", () => {
  fs.writeFileSync(
    "/tmp/sigusr1-received",
    `SIGUSR1 received at ${Date.now()}\n`,
  );
});

// Parse messages from environment or use default
let messages = [];
if (process.env.MESSAGES) {
  try {
    messages = JSON.parse(process.env.MESSAGES);
  } catch (e) {
    console.error("Failed to parse MESSAGES env var:", e.message);
    process.exit(1);
  }
}

// Presets for common test scenarios
if (process.env.PRESET === "normal") {
  messages = [
    { id: 1, type: "input", content: "Hello", time: "2025-01-01T00:00:00Z" },
    {
      id: 2,
      type: "output",
      content: "Hi there",
      time: "2025-01-01T00:00:01Z",
    },
    {
      id: 3,
      type: "input",
      content: "How are you?",
      time: "2025-01-01T00:00:02Z",
    },
    {
      id: 4,
      type: "output",
      content: "Good!",
      time: "2025-01-01T00:00:03Z",
    },
    { id: 5, type: "input", content: "Great", time: "2025-01-01T00:00:04Z" },
  ];
} else if (process.env.PRESET === "many") {
  messages = Array.from({ length: 15 }, (_, i) => ({
    id: i + 1,
    type: "input",
    content: `Message ${i + 1}`,
    time: "2025-01-01T00:00:00Z",
  }));
} else if (process.env.PRESET === "huge") {
  messages = [
    {
      id: 1,
      type: "output",
      content: "x".repeat(70000),
      time: "2025-01-01T00:00:00Z",
    },
  ];
}

const server = http.createServer((req, res) => {
  if (req.url === "/messages") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ messages }));
  } else if (req.url === "/status") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "stable" }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(port, () => {
  console.error(`Mock AgentAPI listening on port ${port}`);
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});

process.on("SIGINT", () => {
  server.close(() => process.exit(0));
});
