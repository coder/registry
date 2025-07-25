#!/bin/bash
set -o errexit
set -o pipefail

# Enhanced logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HOME/.amazon-q-module/logs/start.log"
}

# Create log directory
mkdir -p "$HOME/.amazon-q-module/logs"

log "INFO: Starting Amazon Q module..."

# Module directory matching main.tf
MODULE_DIR="$HOME/.amazon-q-module"
mkdir -p "$MODULE_DIR"

# Add Amazon Q to PATH
export PATH="$PATH:$HOME/q/bin"

# Set up environment variables for task reporting
export CODER_MCP_APP_STATUS_SLUG="amazon-q"
export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"

# Get template variables
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

# Configure MCP if task reporting is enabled
if [ "$REPORT_TASKS" = "true" ]; then
    log "INFO: Configuring MCP for task reporting..."
    
    # Set the workdir for Amazon Q
    WORKDIR="${FOLDER:-/home/coder}"
    
    # Configure MCP with Amazon Q specific settings
    export CODER_MCP_AMAZON_Q_TASK_PROMPT="$TASK_PROMPT"
    export CODER_MCP_AMAZON_Q_SYSTEM_PROMPT="$SYSTEM_PROMPT"
    
    # Run MCP configuration
    coder exp mcp configure amazon-q "$WORKDIR" || {
        log "WARNING: MCP configuration failed, continuing without task reporting"
    }
fi

# Handle task prompt and system prompt
if [ ! -z "$TASK_PROMPT" ]; then
    log "INFO: Starting with task prompt"
    PROMPT="Review your instructions. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $TASK_PROMPT"
    PROMPT_FILE="$MODULE_DIR/prompt.txt"
    echo -n "$PROMPT" > "$PROMPT_FILE"
    
    if [ "$USE_AIDER" = "true" ]; then
        AMAZON_Q_ARGS=(--instructions "$PROMPT_FILE")
    else
        # For Amazon Q, we'll need to pass the prompt differently
        AMAZON_Q_ARGS=()
    fi
else
    log "INFO: Starting without a prompt"
    AMAZON_Q_ARGS=()
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
    
    # Start Aider with AgentAPI
    agentapi server --term-width 67 --term-height 1190 -- \
        bash -c "$(printf '%q ' aider --yes-always "${AMAZON_Q_ARGS[@]}")"
else
    log "INFO: Starting Amazon Q with AgentAPI..."
    
    # Check if Amazon Q is available
    if ! command -v q >/dev/null 2>&1; then
        log "ERROR: Amazon Q is not installed or not in PATH"
        log "INFO: Please run the installation script first"
        exit 1
    fi
    
    # Start Amazon Q via AgentAPI
    # Amazon Q needs the --trust-all-tools flag for automated operation
    agentapi server --term-width 67 --term-height 1190 -- \
        bash -c "export PATH=\"$PATH:$HOME/q/bin\" && q chat --trust-all-tools"
fi