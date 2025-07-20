#!/usr/bin/env bash
set -o errexit
set -o pipefail

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "${BOLD}🦀 OpenAI Codex CLI - Rust-based AI Code Assistant${NC}\n\n"

# Ensure PATH includes ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Check if codex-cli is installed
if ! command -v codex-cli &> /dev/null; then
    printf "${RED}❌ Codex CLI not found. Please ensure the module is properly installed.${NC}\n"
    printf "${YELLOW}💡 This should have been installed automatically by the AgentAPI module.${NC}\n"
    exit 1
fi

# Check if we're in a workspace
if [ -z "$CODER_WORKSPACE_NAME" ]; then
    printf "${YELLOW}⚠️  Not running in a Coder workspace. Some features may be limited.${NC}\n"
fi

# Display help information
printf "${BOLD}📚 Codex CLI Commands:${NC}\n"
printf "  • ${GREEN}codex-cli generate${NC} 'description' - Generate code from description\n"
printf "  • ${GREEN}codex-cli complete${NC} 'partial code' - Complete partial code\n"
printf "  • ${GREEN}codex-cli explain${NC} 'code' - Explain existing code\n"
printf "  • ${GREEN}codex-cli review${NC} 'code' - Review code for issues\n"
printf "  • ${GREEN}codex-cli optimize${NC} 'code' - Optimize code performance\n"
printf "  • ${GREEN}codex-cli debug${NC} 'code' - Help debug code issues\n"
printf "  • ${GREEN}codex-cli test${NC} 'code' - Generate test cases\n"
printf "  • ${GREEN}codex-cli interactive${NC} - Start interactive session\n\n"

printf "${BOLD}🌐 Web Interface:${NC}\n"
printf "  • Access the web chat UI through the Codex app in your Coder workspace\n"
printf "  • Use the integrated Tasks UI for task-based code generation\n"
printf "  • All interactions are logged and reportable through Coder's task system\n\n"

printf "${BOLD}� Configuration:${NC}\n"
printf "  • Config file: ${YELLOW}~/.config/codex/config.toml${NC}\n"
printf "  • Environment variables: ${YELLOW}OPENAI_API_KEY, OPENAI_MODEL, etc.${NC}\n\n"

printf "${BOLD}🚀 Quick Start:${NC}\n"
printf "  1. Set your OpenAI API key: ${YELLOW}export OPENAI_API_KEY='your-key-here'${NC}\n"
printf "  2. Try: ${YELLOW}codex-cli generate 'create a hello world function in Python'${NC}\n"
printf "  3. Or start interactive mode: ${YELLOW}codex-cli interactive${NC}\n\n"

# Show version information
printf "${BOLD}📦 Version Information:${NC}\n"
codex-cli --version
printf "\n"

# Show configuration status
CONFIG_FILE="$HOME/.config/codex/config.toml"
if [ -f "$CONFIG_FILE" ]; then
    printf "${GREEN}✅ Configuration file found${NC}\n"
    printf "${BOLD}🔧 Current settings:${NC}\n"
    if command -v toml &> /dev/null; then
        toml get "$CONFIG_FILE" openai.model 2>/dev/null || echo "  Model: (default)"
        toml get "$CONFIG_FILE" openai.temperature 2>/dev/null || echo "  Temperature: (default)"
    else
        printf "  Model: $(grep 'model =' "$CONFIG_FILE" | cut -d'"' -f2 2>/dev/null || echo '(default)')\n"
        printf "  Temperature: $(grep 'temperature =' "$CONFIG_FILE" | cut -d'=' -f2 | xargs 2>/dev/null || echo '(default)')\n"
    fi
else
    printf "${YELLOW}⚠️  Configuration file not found. Using defaults.${NC}\n"
fi

# Check API key status
if [ -n "$OPENAI_API_KEY" ]; then
    printf "${GREEN}✅ OpenAI API key is set${NC}\n"
else
    printf "${YELLOW}⚠️  OpenAI API key not set. Set it with: export OPENAI_API_KEY='your-key'${NC}\n"
fi

printf "\n${GREEN}🎉 Codex CLI is ready! Use the web interface or CLI commands above.${NC}\n"
