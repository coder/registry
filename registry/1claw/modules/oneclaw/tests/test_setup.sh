#!/bin/bash
# Functional tests for scripts/setup.sh
# Simulates Terraform templatefile substitution, runs the script,
# and verifies the output JSON files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_TEMPLATE="$MODULE_DIR/scripts/setup.sh"

PASS=0
FAIL=0
TESTS_RUN=0
TEST_HOME=""

# ---------- helpers ----------

log_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo ""
  echo "=== TEST $TESTS_RUN: $1 ==="
}

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1" >&2
}

assert_file_exists() {
  if [ -f "$1" ]; then
    pass "$1 exists"
  else
    fail "$1 does not exist"
  fi
}

assert_file_not_exists() {
  if [ ! -f "$1" ]; then
    pass "$1 does not exist (expected)"
  else
    fail "$1 exists but should not"
  fi
}

assert_perms_600() {
  local perms
  perms=$(stat -f '%Lp' "$1" 2> /dev/null || stat -c '%a' "$1" 2> /dev/null)
  if [ "$perms" = "600" ]; then
    pass "$1 has mode 600"
  else
    fail "$1 has mode $perms, expected 600"
  fi
}

assert_valid_json() {
  if python3 -m json.tool "$1" > /dev/null 2>&1; then
    pass "$1 is valid JSON"
  else
    fail "$1 is not valid JSON"
  fi
}

assert_json_key() {
  local file="$1" key_path="$2" expected="$3"
  local actual
  actual=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
keys = sys.argv[2].split('.')
for k in keys:
    d = d[k]
print(d)
" "$file" "$key_path" 2> /dev/null || echo "__MISSING__")
  if [ "$actual" = "$expected" ]; then
    pass "$key_path = $expected"
  else
    fail "$key_path = '$actual', expected '$expected'"
  fi
}

assert_json_has_key() {
  local file="$1" key_path="$2"
  if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
keys = sys.argv[2].split('.')
for k in keys:
    d = d[k]
" "$file" "$key_path" 2> /dev/null; then
    pass "$key_path present"
  else
    fail "$key_path missing"
  fi
}

assert_output_contains() {
  local output="$1" expected="$2"
  if echo "$output" | grep -qF "$expected"; then
    pass "output contains '$expected'"
  else
    fail "output missing '$expected'"
  fi
}

# Render setup.sh by replacing Terraform ${...} placeholders with test values,
# then convert $$ to $ (simulating Terraform templatefile behavior).
# Uses python3 to avoid sed escaping issues with special characters in tokens.
render_script() {
  local mcp_host="$1"
  local vault_id="$2"
  local api_token="$3"
  local install_cursor="$4"
  local install_claude="$5"
  local cursor_path="$6"
  local claude_path="$7"
  local bootstrap_mode="${8:-false}"

  python3 - "$SETUP_TEMPLATE" "$mcp_host" "$vault_id" "$api_token" \
    "$install_cursor" "$install_claude" "$cursor_path" "$claude_path" "$bootstrap_mode" << 'PYEOF'
import sys

template_path = sys.argv[1]
replacements = {
    "${MCP_HOST}": sys.argv[2],
    "${VAULT_ID}": sys.argv[3],
    "${API_TOKEN}": sys.argv[4],
    "${INSTALL_CURSOR_CONFIG}": sys.argv[5],
    "${INSTALL_CLAUDE_CONFIG}": sys.argv[6],
    "${CURSOR_CONFIG_PATH}": sys.argv[7],
    "${CLAUDE_CONFIG_PATH}": sys.argv[8],
    "${BOOTSTRAP_MODE}": sys.argv[9],
}

with open(template_path) as f:
    content = f.read()

for placeholder, value in replacements.items():
    content = content.replace(placeholder, value)

# Simulate Terraform $${...} -> ${...} conversion
content = content.replace("$${", "${")

print(content)
PYEOF
}

# Create an isolated temp HOME, render + run the script, set TEST_HOME.
run_test() {
  TEST_HOME=$(mktemp -d)

  local mcp_host="${1:-https://mcp.1claw.xyz/mcp}"
  local vault_id="${2:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
  local api_token="${3:-ocv_test_token_1234}"
  local install_cursor="${4:-true}"
  local install_claude="${5:-true}"
  local cursor_path="${6:-$TEST_HOME/.cursor/mcp.json}"
  local claude_path="${7:-$TEST_HOME/.config/claude/mcp.json}"

  local rendered
  rendered=$(mktemp)
  render_script "$mcp_host" "$vault_id" "$api_token" \
    "$install_cursor" "$install_claude" "$cursor_path" "$claude_path" \
    > "$rendered"
  chmod +x "$rendered"

  HOME="$TEST_HOME" bash "$rendered"

  rm -f "$rendered"
}

cleanup() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
    TEST_HOME=""
  fi
}

# ---------- test cases ----------

test_fresh_write() {
  log_test "Fresh write — no existing config"
  run_test

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  assert_file_exists "$cursor_cfg"
  assert_valid_json "$cursor_cfg"
  assert_perms_600 "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.X-Vault-ID" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.Authorization" "Bearer ocv_test_token_1234"

  cleanup
}

test_merge_existing() {
  log_test "Merge with existing config"
  TEST_HOME=$(mktemp -d)

  local cursor_dir="$TEST_HOME/.cursor"
  mkdir -p "$cursor_dir"
  cat > "$cursor_dir/mcp.json" << 'EOF'
{
  "mcpServers": {
    "other-tool": {
      "command": "other-mcp-server",
      "args": ["--port", "9090"]
    }
  }
}
EOF

  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
    "ocv_test_token_1234" "true" "false" \
    "$cursor_dir/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  local cursor_cfg="$cursor_dir/mcp.json"
  assert_valid_json "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.other-tool.command" "other-mcp-server"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"

  cleanup
}

test_overwrite_stale() {
  log_test "Overwrite stale 1claw entry"
  TEST_HOME=$(mktemp -d)

  local cursor_dir="$TEST_HOME/.cursor"
  mkdir -p "$cursor_dir"
  cat > "$cursor_dir/mcp.json" << 'EOF'
{
  "mcpServers": {
    "1claw": {
      "url": "https://old-host.example.com/mcp",
      "headers": {
        "Authorization": "Bearer old_token",
        "X-Vault-ID": "00000000-0000-0000-0000-000000000000"
      }
    }
  }
}
EOF

  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
    "ocv_new_token" "true" "false" \
    "$cursor_dir/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  local cursor_cfg="$cursor_dir/mcp.json"
  assert_valid_json "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.Authorization" "Bearer ocv_new_token"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.X-Vault-ID" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  cleanup
}

test_malformed_existing() {
  log_test "Malformed existing config"
  TEST_HOME=$(mktemp -d)

  local cursor_dir="$TEST_HOME/.cursor"
  mkdir -p "$cursor_dir"
  echo "NOT VALID JSON {{{" > "$cursor_dir/mcp.json"

  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
    "ocv_test_token_1234" "true" "false" \
    "$cursor_dir/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  local cursor_cfg="$cursor_dir/mcp.json"
  assert_valid_json "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"

  cleanup
}

test_dual_target() {
  log_test "Dual-target write (Cursor + Claude)"
  run_test "https://mcp.1claw.xyz/mcp" \
    "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "ocv_test_token_1234" \
    "true" "true"

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  local claude_cfg="$TEST_HOME/.config/claude/mcp.json"

  assert_file_exists "$cursor_cfg"
  assert_file_exists "$claude_cfg"
  assert_valid_json "$cursor_cfg"
  assert_valid_json "$claude_cfg"
  assert_json_key "$claude_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"

  cleanup
}

test_skip_disabled() {
  log_test "Skip disabled targets (Claude disabled)"
  run_test "https://mcp.1claw.xyz/mcp" \
    "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "ocv_test_token_1234" \
    "true" "false"

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  local claude_cfg="$TEST_HOME/.config/claude/mcp.json"

  assert_file_exists "$cursor_cfg"
  assert_file_not_exists "$claude_cfg"

  cleanup
}

test_special_chars_in_token() {
  log_test "Special characters in token"
  local nasty_token='ocv_abc+def=ghi&jkl'

  run_test "https://mcp.1claw.xyz/mcp" \
    "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "$nasty_token" \
    "true" "false"

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  assert_file_exists "$cursor_cfg"
  assert_valid_json "$cursor_cfg"
  assert_json_has_key "$cursor_cfg" "mcpServers.1claw.url"

  cleanup
}

# ---------- bootstrap test cases ----------

test_bootstrap_loads_from_state() {
  log_test "Bootstrap — setup.sh loads credentials from bootstrap.json when API_TOKEN is empty"
  TEST_HOME=$(mktemp -d)

  # Simulate what bootstrap.sh would produce
  mkdir -p "$TEST_HOME/.1claw"
  cat > "$TEST_HOME/.1claw/bootstrap.json" << 'EOF'
{
  "vault_id": "11111111-2222-3333-4444-555555555555",
  "agent_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "agent_api_key": "ocv_bootstrapped_key_xyz"
}
EOF
  chmod 600 "$TEST_HOME/.1claw/bootstrap.json"

  # Render setup.sh with empty API_TOKEN and VAULT_ID (bootstrap mode)
  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "" "" \
    "true" "false" \
    "$TEST_HOME/.cursor/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    "true" > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  assert_file_exists "$cursor_cfg"
  assert_valid_json "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.Authorization" "Bearer ocv_bootstrapped_key_xyz"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.X-Vault-ID" "11111111-2222-3333-4444-555555555555"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.url" "https://mcp.1claw.xyz/mcp"

  cleanup
}

test_bootstrap_skips_when_no_creds() {
  log_test "Bootstrap — setup.sh skips gracefully when no creds and no bootstrap.json"
  TEST_HOME=$(mktemp -d)

  # Render with empty API_TOKEN and VAULT_ID, bootstrap_mode=false (no bootstrap expected)
  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "" "" \
    "true" "false" \
    "$TEST_HOME/.cursor/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    "false" > "$rendered"
  chmod +x "$rendered"
  local output
  output=$(HOME="$TEST_HOME" bash "$rendered" 2>&1)
  rm -f "$rendered"

  # Should NOT create any config file
  assert_file_not_exists "$TEST_HOME/.cursor/mcp.json"
  assert_output_contains "$output" "WARNING: No API token or vault ID available"

  cleanup
}

test_bootstrap_state_file_permissions() {
  log_test "Bootstrap — setup.sh reads bootstrap.json with chmod 600"
  TEST_HOME=$(mktemp -d)

  mkdir -p "$TEST_HOME/.1claw"
  cat > "$TEST_HOME/.1claw/bootstrap.json" << 'EOF'
{
  "vault_id": "99999999-8888-7777-6666-555544443333",
  "agent_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  "agent_api_key": "ocv_locked_down_key"
}
EOF
  chmod 600 "$TEST_HOME/.1claw/bootstrap.json"

  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" "" "" \
    "true" "true" \
    "$TEST_HOME/.cursor/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    "true" > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  # Both configs should be created with correct credentials
  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  local claude_cfg="$TEST_HOME/.config/claude/mcp.json"
  assert_file_exists "$cursor_cfg"
  assert_file_exists "$claude_cfg"
  assert_perms_600 "$cursor_cfg"
  assert_perms_600 "$claude_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.X-Vault-ID" "99999999-8888-7777-6666-555544443333"
  assert_json_key "$claude_cfg" "mcpServers.1claw.headers.X-Vault-ID" "99999999-8888-7777-6666-555544443333"

  cleanup
}

test_direct_creds_take_priority() {
  log_test "Direct credentials take priority over bootstrap.json"
  TEST_HOME=$(mktemp -d)

  # Put stale/different creds in bootstrap.json
  mkdir -p "$TEST_HOME/.1claw"
  cat > "$TEST_HOME/.1claw/bootstrap.json" << 'EOF'
{
  "vault_id": "stale-vault-id-should-not-be-used",
  "agent_id": "stale-agent-id",
  "agent_api_key": "ocv_stale_bootstrap_key"
}
EOF

  # Render with real direct credentials
  local rendered
  rendered=$(mktemp)
  render_script "https://mcp.1claw.xyz/mcp" \
    "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "ocv_direct_key_wins" \
    "true" "false" \
    "$TEST_HOME/.cursor/mcp.json" "$TEST_HOME/.config/claude/mcp.json" \
    > "$rendered"
  chmod +x "$rendered"
  HOME="$TEST_HOME" bash "$rendered"
  rm -f "$rendered"

  local cursor_cfg="$TEST_HOME/.cursor/mcp.json"
  assert_valid_json "$cursor_cfg"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.Authorization" "Bearer ocv_direct_key_wins"
  assert_json_key "$cursor_cfg" "mcpServers.1claw.headers.X-Vault-ID" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  cleanup
}

# ---------- runner ----------

echo "Running 1Claw Coder Workspace Module tests..."
echo "Module dir: $MODULE_DIR"
echo ""

test_fresh_write
test_merge_existing
test_overwrite_stale
test_malformed_existing
test_dual_target
test_skip_disabled
test_special_chars_in_token
test_bootstrap_loads_from_state
test_bootstrap_skips_when_no_creds
test_bootstrap_state_file_permissions
test_direct_creds_take_priority

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed (out of $TESTS_RUN tests)"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
