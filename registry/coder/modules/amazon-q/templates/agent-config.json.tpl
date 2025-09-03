{
  "name": "agent",
  "description": "This is an default agent config",
  "prompt": ${system_prompt},
  "mcpServers": {},
  "tools": [
    "fs_read",
    "fs_write",
    "execute_bash",
    "use_aws",
    "@coder",
    "knowledge"
  ],
  "toolAliases": {},
  "allowedTools": [
    "fs_read",
    "@coder"
  ],
  "resources": [
    "file://AmazonQ.md",
    "file://README.md",
    "file://.amazonq/rules/**/*.md"
  ],
  "hooks": {},
  "toolsSettings": {},
  "useLegacyMcpJson": true
}
