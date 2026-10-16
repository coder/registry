# shellcheck shell=bash
# Pre-agent log API client; failures never prevent boot.
CODER_LOG_BUDGET="${CODER_LOG_BUDGET:-524288}"
CODER_LOG_STATE_DIR="${CODER_LOG_STATE_DIR:-/run/coder}"
CODER_LOG_MAX_LINE=2048
CODER_LOG_FLUSH_SECS="${CODER_LOG_FLUSH_SECS:-5}"
CODER_LOG_READY="${CODER_LOG_READY:-0}"

_curl() {
  if [ -z "${CODER_CURL:-}" ]; then
    CODER_CURL=$(command -v curl) || return 1
    export CODER_CURL
  fi
  "$CODER_CURL" "$@"
}

# A rejected overflow permanently silences every log source on this agent.
coder_log_budget_left() {
  local used
  used=$(cat "$CODER_LOG_STATE_DIR/log-budget" 2> /dev/null || echo 0)
  echo $((CODER_LOG_BUDGET - used))
}

coder_log_budget_add() {
  local used
  used=$(cat "$CODER_LOG_STATE_DIR/log-budget" 2> /dev/null || echo 0)
  echo $((used + $1)) > "$CODER_LOG_STATE_DIR/log-budget"
}

coder_log_init() {
  local attempt=0 code
  command -v curl > /dev/null 2>&1 || return 1
  mkdir -p "$CODER_LOG_STATE_DIR" || return 1
  while [ "$attempt" -lt 40 ]; do
    code=$(
      _curl -sS -o /dev/null -w '%{http_code}' -X POST \
        "$CODER_ACCESS_URL/api/v2/workspaceagents/me/log-source" \
        -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
        -H 'Content-Type: application/json' \
        --data-binary "$CODER_LOG_REGISTRATION" || echo 000
    )
    case "$code" in
      200 | 201)
        export CODER_LOG_READY=1
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
  local payload request size lock="$CODER_LOG_STATE_DIR/log-budget.lock" tries=0
  payload=$(paste -sd, -) || return 0
  [ -n "$payload" ] || return 0
  request="{\"log_source_id\":\"$CODER_LOG_SOURCE_ID\",\"logs\":[$payload]}"
  size=$(printf '%s' "$request" | LC_ALL=C wc -c)
  # mkdir is an atomic cross-process lock; fail closed if a writer is stuck.
  while ! mkdir "$lock" 2> /dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 40 ] || return 0
    sleep 0.05
  done
  if [ "$(coder_log_budget_left)" -lt "$size" ] || ! coder_log_budget_add "$size"; then
    rmdir "$lock"
    return 0
  fi
  rmdir "$lock"
  _curl -sS -o /dev/null -X PATCH \
    "$CODER_ACCESS_URL/api/v2/workspaceagents/me/logs" \
    -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "$request" || true
}

coder_log() {
  local level="$1"
  shift
  [ "$CODER_LOG_READY" = 1 ] || return 0
  coder_log_json "$level" "$*" | coder_log_send
}

# Flush slow producers as well as full batches.
coder_log_pipe() {
  local level="${1:-info}" line batch="" n=0 bytes=0 obj rc now last
  [ "$CODER_LOG_READY" = 1 ] || {
    cat > /dev/null
    return 0
  }
  last=$(date +%s)
  while :; do
    line=""
    if IFS= read -r -t "$CODER_LOG_FLUSH_SECS" line; then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && [ "$rc" -le 128 ]; then
      if [ -n "$line" ]; then
        obj=$(coder_log_json "$level" "$line")
        batch="${batch:+$batch
}$obj"
      fi
      break
    fi
    if [ -n "$line" ]; then
      obj=$(coder_log_json "$level" "$line")
      batch="${batch:+$batch
}$obj"
      n=$((n + 1))
      bytes=$((bytes + $(printf '%s' "$obj" | LC_ALL=C wc -c)))
    fi
    now=$(date +%s)
    if [ "$n" -ge 50 ] || [ "$bytes" -ge 32768 ] \
      || { [ "$n" -gt 0 ] && [ "$((now - last))" -ge "$CODER_LOG_FLUSH_SECS" ]; }; then
      printf '%s\n' "$batch" | coder_log_send
      batch=""
      n=0
      bytes=0
      last=$now
    fi
  done
  [ -z "$batch" ] || printf '%s\n' "$batch" | coder_log_send
  return 0
}

coder_log_tail() {
  local file="$1" lines="${2:-200}"
  [ -f "$file" ] || return 0
  coder_log error "--- last $lines lines of $file ---"
  tail -n "$lines" "$file" | coder_log_pipe error
}
