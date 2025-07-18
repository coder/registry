#!/bin/bash
set -o errexit
set -o pipefail

# Enhanced logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HOME/.amazon-q-module/logs/start.log"
}

# Create log directory
mkdir -p "$HOME/.amazon-q-module/logs"

log "INFO: Starting Amazon Q..."

# Add Amazon Q to PATH
export PATH="$PATH:$HOME/q/bin"

# Set up environment variables for task reporting
export CODER_MCP_APP_STATUS_SLUG="amazon-q"
export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"

# Create module directory
MODULE_DIR="$HOME/.amazon-q-module"
mkdir -p "$MODULE_DIR"

# Template variables from Terraform
SYSTEM_PROMPT="${system_prompt}"
TASK_PROMPT="${task_prompt}"
FOLDER="${folder}"
USE_AIDER="${use_aider}"
REPORT_TASKS="${report_tasks}"

# Set AWS environment variables
export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
export AWS_REGION="${aws_region}"
export AWS_PROFILE="${aws_profile}"

# Handle system prompt
if [ ! -z "$SYSTEM_PROMPT" ]; then
    log "INFO: Setting system prompt"
    echo "$SYSTEM_PROMPT" > "$MODULE_DIR/system_prompt.txt"
fi

# Handle task prompt
if [ ! -z "$TASK_PROMPT" ]; then
    log "INFO: Starting with task prompt"
    echo "$TASK_PROMPT" > "$MODULE_DIR/task_prompt.txt"
    
    # Create combined prompt
    COMBINED_PROMPT="You are Amazon Q, an AI coding assistant. Follow these instructions:\n\n"
    
    if [ -f "$MODULE_DIR/system_prompt.txt" ]; then
        COMBINED_PROMPT="$${COMBINED_PROMPT}$(cat $MODULE_DIR/system_prompt.txt)\n\n"
    fi
    
    COMBINED_PROMPT="$${COMBINED_PROMPT}Current task: $(cat $MODULE_DIR/task_prompt.txt)"
    
    log "INFO: Using combined prompt for task execution"
else
    log "INFO: Starting without specific task prompt"
fi

# Signal handling for graceful shutdown
cleanup() {
    log "INFO: Received shutdown signal, cleaning up..."
    exit 0
}
trap cleanup SIGTERM SIGINT

# Change to the specified folder
cd "$FOLDER"

# Check if we should use Aider or Amazon Q
if [ "$USE_AIDER" = "true" ]; then
    log "INFO: Starting Aider with AgentAPI..."
    
    # Check if Aider is available
    if ! command -v aider >/dev/null 2>&1; then
        log "ERROR: Aider is not installed or not in PATH"
        log "INFO: Please install Aider first: pip install aider-chat"
        exit 1
    fi
    
    # Start Aider with the system prompt and task
    if [ -n "$TASK_PROMPT" ]; then
        FULL_PROMPT="SYSTEM PROMPT:\n$SYSTEM_PROMPT\n\nThis is your current task: $TASK_PROMPT"
        echo -e "$FULL_PROMPT" | agentapi server --term-width 67 --term-height 1190 -- \
            aider --yes-always 2>&1 | tee -a "$HOME/.aider.log"
    else
        agentapi server --term-width 67 --term-height 1190 -- \
            aider 2>&1 | tee -a "$HOME/.aider.log"
    fi
else
    log "INFO: Starting Amazon Q with AgentAPI..."
    
    # Check if Amazon Q is available
    if ! command -v q >/dev/null 2>&1; then
        log "ERROR: Amazon Q is not installed or not in PATH"
        log "INFO: Please run the installation script first"
        exit 1
    fi
    
    # Start Amazon Q via AgentAPI
    if [ "$REPORT_TASKS" = "true" ]; then
        log "INFO: Starting with MCP task reporting support"
        agentapi server --term-width 67 --term-height 1190 -- \
            bash -c "export PATH=\"$PATH:$HOME/q/bin\" && q chat --trust-all-tools"
    else
        log "INFO: Starting without MCP task reporting"
        agentapi server --term-width 67 --term-height 1190 -- \
            bash -c "export PATH=\"$PATH:$HOME/q/bin\" && q chat"
    fi
fi