#!/bin/bash
# Test utility for Codex CLI module

set -e

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BOLD}🧪 Testing Codex CLI Module...${NC}"

# Test 1: Check if configuration is properly created
echo -e "${YELLOW}Test 1: Configuration creation${NC}"
if [ -f "$HOME/.config/codex/config.toml" ]; then
    echo -e "${GREEN}✅ Configuration file exists${NC}"
else
    echo -e "${RED}❌ Configuration file missing${NC}"
    exit 1
fi

# Test 2: Check if scripts are executable
echo -e "${YELLOW}Test 2: Script permissions${NC}"
if [ -x "$HOME/.local/bin/codex-agentapi-bridge" ]; then
    echo -e "${GREEN}✅ Bridge script is executable${NC}"
else
    echo -e "${RED}❌ Bridge script missing or not executable${NC}"
    exit 1
fi

# Test 3: Check if AgentAPI configuration is created
echo -e "${YELLOW}Test 3: AgentAPI configuration${NC}"
if [ -f "$HOME/.config/codex/agentapi.json" ]; then
    echo -e "${GREEN}✅ AgentAPI configuration exists${NC}"
else
    echo -e "${RED}❌ AgentAPI configuration missing${NC}"
    exit 1
fi

# Test 4: Mock API call test
echo -e "${YELLOW}Test 4: Mock API response${NC}"
if command -v jq &> /dev/null; then
    echo '{"type": "generate", "content": "hello world"}' | jq . > /tmp/test_input.json
    if [ -f /tmp/test_input.json ]; then
        echo -e "${GREEN}✅ JSON parsing works${NC}"
    else
        echo -e "${RED}❌ JSON parsing failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  jq not available, skipping JSON test${NC}"
fi

# Test 5: Environment variable test
echo -e "${YELLOW}Test 5: Environment variables${NC}"
if [ -n "$OPENAI_MODEL" ]; then
    echo -e "${GREEN}✅ OPENAI_MODEL is set to: $OPENAI_MODEL${NC}"
else
    echo -e "${YELLOW}⚠️  OPENAI_MODEL not set, using default${NC}"
fi

echo -e "\n${GREEN}🎉 All tests passed!${NC}"
