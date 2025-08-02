#!/bin/bash
set -o errexit
set -o pipefail

# Template variables
OPENAI_API_KEY="${OPENAI_API_KEY}"
OPENAI_MODEL="${OPENAI_MODEL}"
TEMPERATURE="${TEMPERATURE}"
MAX_TOKENS="${MAX_TOKENS}"
FOLDER="${FOLDER}"
AI_PROMPT="${AI_PROMPT}"

# AgentAPI parameters
USE_AGENTAPI="$${1:-true}"
AGENTAPI_PORT="$${2:-3284}"

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "$${BOLD}🚀 Starting Codex CLI with AgentAPI integration...$${NC}\n\n"

# Set up environment variables
export OPENAI_API_KEY="$OPENAI_API_KEY"
export OPENAI_MODEL="$OPENAI_MODEL"
export CODEX_TEMPERATURE="$TEMPERATURE"
export CODEX_MAX_TOKENS="$MAX_TOKENS"
export CODEX_FOLDER="$FOLDER"
export CODEX_AI_PROMPT="$AI_PROMPT"

# Ensure PATH includes ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Check if codex-cli is installed
if ! command -v codex-cli &> /dev/null; then
    printf "$${RED}❌ Codex CLI not found. Please ensure it's installed.$${NC}\n"
    exit 1
fi

# Check if OpenAI API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    printf "$${YELLOW}⚠️  OpenAI API key not set. Using default configuration.$${NC}\n"
fi

# Update configuration with environment variables
CONFIG_FILE="$HOME/.config/codex/config.toml"
mkdir -p "$HOME/.config/codex"
cat > "$CONFIG_FILE" << EOF
[openai]
model = "$OPENAI_MODEL"
temperature = $TEMPERATURE
max_tokens = $MAX_TOKENS

[codex]
auto_save = true
show_thinking = true
verbose = false
working_directory = "$FOLDER"

[ui]
theme = "dark"
highlight_syntax = true

[agentapi]
enabled = $USE_AGENTAPI
port = $AGENTAPI_PORT
host = "localhost"
EOF

printf "${GREEN}✅ Configuration updated${NC}\n"

# Handle AI prompt for task reporting
if [ -n "$AI_PROMPT" ]; then
    printf "${YELLOW}📝 Setting up AI prompt for task reporting...${NC}\n"
    echo -n "$AI_PROMPT" > /tmp/codex-prompt.txt
    printf "${GREEN}✅ AI prompt configured${NC}\n"
fi

# Change to the working directory
cd "$FOLDER"

# Create AgentAPI bridge script
BRIDGE_SCRIPT="$HOME/.local/bin/codex-agentapi-bridge"
cat > "$BRIDGE_SCRIPT" << 'BRIDGE_EOF'
#!/bin/bash
set -e

# Environment setup
export PATH="$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Function to handle different types of requests
handle_request() {
    local request_type="$1"
    local content="$2"
    
    case "$request_type" in
        "generate")
            codex-cli generate "$content"
            ;;
        "complete")
            codex-cli complete "$content"
            ;;
        "explain")
            codex-cli explain "$content"
            ;;
        "review")
            codex-cli review "$content"
            ;;
        "optimize")
            codex-cli optimize "$content"
            ;;
        "debug")
            codex-cli debug "$content"
            ;;
        "test")
            codex-cli test "$content"
            ;;
        "interactive")
            codex-cli interactive
            ;;
        *)
            # Default to generate for unknown request types
            codex-cli generate "$content"
            ;;
    esac
}

# Main execution
if [ $# -eq 0 ]; then
    # No arguments - start interactive mode
    handle_request "interactive" ""
else
    # Use first argument as command, rest as content
    handle_request "$1" "$${*:2}"
fi
BRIDGE_EOF

chmod +x "$BRIDGE_SCRIPT"

printf "${GREEN}✅ AgentAPI bridge configured${NC}\n\n"

# Test the installation
printf "${BOLD}🧪 Testing Codex CLI...${NC}\n"
if codex-cli --version >/dev/null 2>&1; then
    printf "${GREEN}✅ Codex CLI is responding correctly${NC}\n"
else
    printf "${RED}❌ Codex CLI test failed${NC}\n"
    exit 1
fi

printf "\n${GREEN}🎉 Codex CLI is ready for AgentAPI integration!${NC}\n"
printf "${BOLD}📚 Available commands:${NC}\n"
printf "  • ${YELLOW}generate${NC} - Generate code from description\n"
printf "  • ${YELLOW}complete${NC} - Complete partial code\n"
printf "  • ${YELLOW}explain${NC} - Explain existing code\n"
printf "  • ${YELLOW}review${NC} - Review code for issues\n"
printf "  • ${YELLOW}optimize${NC} - Optimize code performance\n"
printf "  • ${YELLOW}debug${NC} - Help debug code issues\n"
printf "  • ${YELLOW}test${NC} - Generate test cases\n"
printf "  • ${YELLOW}interactive${NC} - Start interactive session\n\n"

# Start the AgentAPI server
if [ "$USE_AGENTAPI" = "true" ]; then
    printf "${BOLD}🔄 Starting AgentAPI server on port $AGENTAPI_PORT...${NC}\n"
    
    # Create a simple AgentAPI configuration for Codex
    cat > "$HOME/.config/codex/agentapi.json" << JSON_EOF
{
  "name": "Codex CLI",
  "version": "1.0.0",
  "description": "Rust-based OpenAI Codex CLI with AgentAPI integration",
  "commands": {
    "generate": {
      "description": "Generate code from description",
      "handler": "codex-agentapi-bridge"
    },
    "complete": {
      "description": "Complete partial code",
      "handler": "codex-agentapi-bridge"
    },
    "explain": {
      "description": "Explain existing code",
      "handler": "codex-agentapi-bridge"
    },
    "review": {
      "description": "Review code for issues",
      "handler": "codex-agentapi-bridge"
    },
    "optimize": {
      "description": "Optimize code performance",
      "handler": "codex-agentapi-bridge"
    },
    "debug": {
      "description": "Help debug code issues",
      "handler": "codex-agentapi-bridge"
    },
    "test": {
      "description": "Generate test cases",
      "handler": "codex-agentapi-bridge"
    },
    "interactive": {
      "description": "Start interactive session",
      "handler": "codex-agentapi-bridge"
    }
  }
}
JSON_EOF

    # Start AgentAPI with our configuration
    exec agentapi --config "$HOME/.config/codex/agentapi.json" --port "$AGENTAPI_PORT" --handler "$BRIDGE_SCRIPT"
else
    printf "${YELLOW}⚠️  AgentAPI disabled. Running in standalone mode.${NC}\n"
    exec codex-cli interactive
fi
