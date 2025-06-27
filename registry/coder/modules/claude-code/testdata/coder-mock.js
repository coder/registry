#!/usr/bin/env node

const fs = require("fs");

const statusSlugEnvVar = "CODER_MCP_APP_STATUS_SLUG";
const agentApiUrlEnvVar = "CODER_MCP_AI_AGENTAPI_URL";

fs.writeFileSync(
  "/home/coder/coder-mock-output.json",
  JSON.stringify({
    statusSlug: process.env[statusSlugEnvVar] ?? "env var not set",
    agentApiUrl: process.env[agentApiUrlEnvVar] ?? "env var not set",
  }),
);
