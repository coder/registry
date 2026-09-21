# shellcheck shell=bash
#
# Pushes lines to the Coder agent log API -- the only way to show anything in
# the workspace UI before the agent exists, which on a first boot lasts for as
# long as the boot script runs.
#
# Callers set CODER_ACCESS_URL, CODER_AGENT_TOKEN, CODER_LOG_SOURCE_ID and
# optionally CODER_LOG_BUDGET. Sets no shell options: failing to log must
# never be fatal.

CODER_LOG_BUDGET="${CODER_LOG_BUDGET:-524288}"
CODER_LOG_STATE_DIR="${CODER_LOG_STATE_DIR:-/run/coder}"
CODER_LOG_MAX_LINE=2048
CODER_LOG_FLUSH_SECS="${CODER_LOG_FLUSH_SECS:-5}"
# Inherited, so a child process that sources this library can log without
# registering the source again -- registration is per workspace build, not per
# process, and a child has no way to know whether it already happened.
CODER_LOG_READY="${CODER_LOG_READY:-0}"

# Resolved once. An image without curl gets no logs: every function here then
# fails closed, which is the right trade -- logging must never be the reason a
# boot fails.
coder_curl() {
  if [ -z "${CODER_CURL:-}" ]; then
    command -v curl > /dev/null 2>&1 || return 1
    CODER_CURL=$(command -v curl)
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
#
# Batches are flushed by size, and also by time: a slow producer would
# otherwise sit in the buffer until 50 lines had accumulated, which reads as a
# hung workspace, and anything still buffered when the process is killed is
# simply lost.
coder_log_pipe() {
  local level="${1:-info}" line batch="" n=0 bytes=0 obj rc now last
  [ "$CODER_LOG_READY" = 1 ] || {
    cat > /dev/null
    return 0
  }
  last=$(date +%s)

  while :; do
    line=""
    # Not `if ! read`: `!` rewrites $? to 0, which turns every timeout into an
    # end of input and ends the stream after the first quiet interval.
    IFS= read -r -t "$CODER_LOG_FLUSH_SECS" line
    rc=$?

    # read(1) returns >128 on timeout; any other failure is end of input,
    # possibly with a last line that had no newline.
    if [ "$rc" -ne 0 ] && [ "$rc" -le 128 ]; then
      if [ -n "$line" ]; then
        batch="${batch:+$batch
}$(coder_log_json "$level" "$line")"
      fi
      break
    fi

    if [ -n "$line" ]; then
      obj=$(coder_log_json "$level" "$line")
      batch="${batch:+$batch
}$obj"
      n=$((n + 1))
      bytes=$((bytes + ${#obj}))
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

# Tail of a failed transcript, so the UI shows the actual error.
coder_log_tail() {
  local file="$1" lines="${2:-200}"
  [ -f "$file" ] || return 0
  coder_log error "--- last $lines lines of $file ---"
  tail -n "$lines" "$file" | coder_log_pipe error
}
