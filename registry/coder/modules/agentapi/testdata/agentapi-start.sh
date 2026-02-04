#!/bin/bash
set -o errexit
set -o pipefail

module_path="$HOME/.agentapi-module"

# Write the agent command to agent-command.sh
cat > "$module_path/agent-command.sh" << 'EOF'
#!/bin/bash
exec bash -c aiagent
EOF

chmod +x "$module_path/agent-command.sh"

echo "Agent command written to $module_path/agent-command.sh"

echo "Using AGENTAPI_CHAT_BASE_PATH: ${AGENTAPI_CHAT_BASE_PATH:-not set}" >> /home/coder/test-agentapi-start.log
