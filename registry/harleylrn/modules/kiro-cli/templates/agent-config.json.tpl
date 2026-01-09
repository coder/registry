{
  "name": "agent",
  "description": "This is an default agent config",
  "prompt": ${system_prompt},
  "mcpServers": {},
  "tools": [
    "read",
    "write",
    "shell",
    "aws",
    "@coder",
    "knowledge"
  ],
  "toolAliases": {},
  "allowedTools": [
    "read",
    "@coder"
  ],
  "resources": [
    "file://KiroQ.md",
    "file://README.md",
    "file://.kiro/steering/**/*.md"
  ],
  "hooks": {},
  "toolsSettings": {},
  "useLegacyMcpJson": true
}
