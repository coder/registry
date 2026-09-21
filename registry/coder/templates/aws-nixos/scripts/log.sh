# shellcheck shell=bash
#
# Pushes lines to the Coder agent log API -- the only way to show anything in
# the workspace UI before the agent exists, which on first boot is the whole
# duration of the NixOS switch.
#
# Callers set CODER_ACCESS_URL, CODER_AGENT_TOKEN, CODER_LOG_SOURCE_ID and
# optionally CODER_LOG_BUDGET. Sets no shell options: failing to log must
# never be fatal.

CODER_LOG_BUDGET="${CODER_LOG_BUDGET:-524288}"
CODER_LOG_STATE_DIR="${CODER_LOG_STATE_DIR:-/run/coder}"
CODER_LOG_MAX_LINE=2048
CODER_LOG_READY=0

# amazon-init's PATH has no curl. Resolve once; `nix shell` per call would add
# an evaluation to every batch.
coder_curl() {
  if [ -z "${CODER_CURL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      CODER_CURL=$(command -v curl)
    else
      CODER_CURL="$(nix build --no-link --print-out-paths nixpkgs#curl 2> /dev/null)/bin/curl"
    fi
    [ -x "$CODER_CURL" ] || return 1
    export CODER_CURL
  fi
  "$CODER_CURL" "$@"
}

# Coder caps agent logs at 1 MiB per AGENT, shared across every log source.
# Overflowing does not truncate: the batch is rejected and the agent is
# flagged overflowed permanently, silently dropping all later logs from every
# source. So track our own usage and go quiet before the server says no.
coder_log_budget_left() {
  local used
  used=$(cat "$CODER_LOG_STATE_DIR/log-budget" 2> /dev/null || echo 0)
  echo $((CODER_LOG_BUDGET - used))
}

coder_log_budget_add() {
  local used
  used=$(cat "$CODER_LOG_STATE_DIR/log-budget" 2> /dev/null || echo 0)
  echo $((used + $1)) > "$CODER_LOG_STATE_DIR/log-budget" 2> /dev/null || true
}

# Idempotent: Coder swallows a duplicate id, so this can run on every boot
# with a fixed UUID. Retries on 401 because the agent record is only created
# when the provisioner job completes -- an instance can boot before then.
coder_log_init() {
  local display_name="$1" icon="$2" attempt=0 code
  mkdir -p "$CODER_LOG_STATE_DIR" 2> /dev/null || true

  while [ "$attempt" -lt 40 ]; do
    code=$(
      coder_curl -sS -o /dev/null -w '%{http_code}' -X POST \
        "$CODER_ACCESS_URL/api/v2/workspaceagents/me/log-source" \
        -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
        -H 'Content-Type: application/json' \
        --data-binary @- << JSON || echo 000
{"id":"$CODER_LOG_SOURCE_ID","display_name":"$display_name","icon":"$icon"}
JSON
    )
    case "$code" in
      # The handler returns 201 on both create and already-exists.
      200 | 201)
        CODER_LOG_READY=1
        return 0
        ;;
      401 | 403 | 000 | 5??)
        attempt=$((attempt + 1))
        sleep 15
        ;;
      *) return 1 ;;
    esac
  done
  return 1
}

coder_log_json() {
  local level="$1" line="$2"
  [ "${#line}" -le "$CODER_LOG_MAX_LINE" ] || line="${line:0:$CODER_LOG_MAX_LINE}..."
  line=$(printf '%s' "$line" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//g' -e 's/\t/  /g')
  printf '{"created_at":"%s","level":"%s","output":"%s"}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$line"
}

coder_log_send() {
  local payload size
  payload=$(paste -sd, -)
  [ -n "$payload" ] || return 0

  size=${#payload}
  [ "$(coder_log_budget_left)" -gt "$size" ] || return 0
  coder_log_budget_add "$size"

  coder_curl -sS -o /dev/null -X PATCH \
    "$CODER_ACCESS_URL/api/v2/workspaceagents/me/logs" \
    -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary @- << JSON || true
{"log_source_id":"$CODER_LOG_SOURCE_ID","logs":[$payload]}
JSON
}

coder_log() {
  local level="$1"
  shift
  [ "$CODER_LOG_READY" = 1 ] || return 0
  coder_log_json "$level" "$*" | coder_log_send
}

# Reads plain lines on stdin and ships them in batches.
coder_log_pipe() {
  local level="${1:-info}" line batch="" n=0 bytes=0 obj
  [ "$CODER_LOG_READY" = 1 ] || {
    cat > /dev/null
    return 0
  }

  while IFS= read -r line || [ -n "$line" ]; do
    obj=$(coder_log_json "$level" "$line")
    batch="${batch:+$batch
}$obj"
    n=$((n + 1))
    bytes=$((bytes + ${#obj}))
    if [ "$n" -ge 50 ] || [ "$bytes" -ge 32768 ]; then
      printf '%s\n' "$batch" | coder_log_send
      batch=""
      n=0
      bytes=0
    fi
  done

  [ -z "$batch" ] || printf '%s\n' "$batch" | coder_log_send
  return 0
}

# Tail of a failed transcript, so the UI shows the actual error.
coder_log_tail() {
  local file="$1" lines="${2:-200}"
  [ -f "$file" ] || return 0
  coder_log error "--- last $lines lines of $file ---"
  tail -n "$lines" "$file" | coder_log_pipe error
}
