#!/usr/bin/env bash
# AgentAPI shutdown script.
#
# Performs a graceful shutdown of AgentAPI: sends SIGUSR1 to trigger state save,
# captures the last 10 messages as a log snapshot posted to the Coder instance,
# then sends SIGTERM for graceful termination.

set -euo pipefail

# Configuration (set via Terraform interpolation).
readonly TASK_ID="${ARG_TASK_ID:-}"
readonly TASK_LOG_SNAPSHOT="${ARG_TASK_LOG_SNAPSHOT:-true}"
readonly AGENTAPI_PORT="${ARG_AGENTAPI_PORT:-3284}"
readonly ENABLE_STATE_PERSISTENCE="${ARG_ENABLE_STATE_PERSISTENCE:-false}"
readonly MODULE_DIR_NAME="${ARG_MODULE_DIR_NAME:-}"
readonly PID_FILE_PATH="${ARG_PID_FILE_PATH:-${MODULE_DIR_NAME:+$HOME/$MODULE_DIR_NAME/agentapi.pid}}"

# Source shared utilities (written by the coder_script wrapper).
# shellcheck source=lib.sh
source /tmp/agentapi-lib.sh

# Runtime environment variables.
readonly CODER_AGENT_URL="${CODER_AGENT_URL:-}"
readonly CODER_AGENT_TOKEN="${CODER_AGENT_TOKEN:-}"

# Constants.
readonly MAX_PAYLOAD_SIZE=65536    # 64KB
readonly MAX_MESSAGE_CONTENT=57344 # 56KB
readonly MAX_MESSAGES=10
readonly FETCH_TIMEOUT=5
readonly POST_TIMEOUT=10

log() {
  echo "$*"
}

error() {
  echo "Error: $*" >&2
}

fetch_and_build_messages_payload() {
  local payload_file="$1"
  local messages_url="http://localhost:${AGENTAPI_PORT}/messages"

  log "Fetching messages from AgentAPI on port $AGENTAPI_PORT"

  if ! curl -fsSL --max-time "$FETCH_TIMEOUT" "$messages_url" > "$payload_file"; then
    error "Failed to fetch messages from AgentAPI (may not be running)"
    return 1
  fi

  # Update messages field to keep only last N messages.
  if ! jq --argjson n "$MAX_MESSAGES" '.messages |= .[-$n:]' < "$payload_file" > "${payload_file}.tmp"; then
    error "Failed to select last $MAX_MESSAGES messages"
    return 1
  fi
  mv "${payload_file}.tmp" "$payload_file"

  return 0
}

truncate_messages_payload_to_size() {
  local payload_file="$1"
  local max_size="$2"

  while true; do
    local size
    size=$(wc -c < "$payload_file")

    if ((size <= max_size)); then
      break
    fi

    local count
    count=$(jq '.messages | length' < "$payload_file")

    if ((count == 1)); then
      # Down to last message, truncate its content keeping the tail.
      log "Payload size $size bytes exceeds limit, truncating final message content"

      # Keep tail of content with truncation indicator, leaving room for JSON
      # overhead.
      if ! jq --argjson maxlen "$MAX_MESSAGE_CONTENT" '.messages[0].content |= (if length > $maxlen then "[...content truncated, showing last 56KB...]\n\n" + .[-$maxlen:] else . end)' < "$payload_file" > "${payload_file}.tmp"; then
        error "Failed to truncate message content"
        return 1
      fi
      mv "${payload_file}.tmp" "$payload_file"

      # Verify the truncation was sufficient.
      size=$(wc -c < "$payload_file")
      if ((size > max_size)); then
        error "Payload still too large after content truncation, giving up"
        return 1
      fi
      break
    else
      # More than one message, remove the oldest.
      log "Payload size $size bytes exceeds limit, removing oldest message"

      if ! jq '.messages |= .[1:]' < "$payload_file" > "${payload_file}.tmp"; then
        error "Failed to remove oldest message"
        return 1
      fi
      mv "${payload_file}.tmp" "$payload_file"
    fi
  done

  return 0
}

post_task_log_snapshot() {
  local payload_file="$1"
  local tmpdir="$2"

  local snapshot_url="${CODER_AGENT_URL}/api/v2/workspaceagents/me/tasks/${TASK_ID}/log-snapshot?format=agentapi"
  local response_file="${tmpdir}/response.txt"

  log "Posting log snapshot to Coder instance"

  local http_code
  if ! http_code=$(curl -sS -w "%{http_code}" -o "$response_file" \
    --max-time "$POST_TIMEOUT" \
    -X POST "$snapshot_url" \
    -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$payload_file"); then
    error "Failed to connect to Coder instance (curl failed)"
    return 1
  fi

  if [[ $http_code == 204 ]]; then
    log "Log snapshot posted successfully"
    return 0
  elif [[ $http_code == 404 ]]; then
    log "Log snapshot endpoint not supported by this Coder version, skipping"
    return 0
  else
    local response
    response=$(cat "$response_file" 2> /dev/null || echo "")
    error "Failed to post log snapshot (HTTP $http_code): $response"
    return 1
  fi
}

capture_task_log_snapshot() {
  if [[ -z $TASK_ID ]]; then
    log "No task ID, skipping log snapshot"
    return 0
  fi

  if [[ -z $CODER_AGENT_URL ]]; then
    error "CODER_AGENT_URL not set, cannot capture log snapshot"
    return 1
  fi

  if [[ -z $CODER_AGENT_TOKEN ]]; then
    error "CODER_AGENT_TOKEN not set, cannot capture log snapshot"
    return 1
  fi

  if ! command -v jq > /dev/null 2>&1; then
    error "jq not found, cannot capture log snapshot"
    return 1
  fi

  if ! command -v curl > /dev/null 2>&1; then
    error "curl not found, cannot capture log snapshot"
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  local payload_file="${tmpdir}/payload.json"

  if ! fetch_and_build_messages_payload "$payload_file"; then
    error "Cannot capture log snapshot without messages"
    return 1
  fi

  local message_count
  message_count=$(jq '.messages | length' < "$payload_file")
  if ((message_count == 0)); then
    log "No messages for log snapshot"
    return 0
  fi

  log "Retrieved $message_count messages for log snapshot"

  # Ensure payload fits within size limit.
  if ! truncate_messages_payload_to_size "$payload_file" "$MAX_PAYLOAD_SIZE"; then
    error "Failed to truncate payload to size limit"
    return 1
  fi

  local final_size final_count
  final_size=$(wc -c < "$payload_file")
  final_count=$(jq '.messages | length' < "$payload_file")
  log "Log snapshot payload: $final_size bytes, $final_count messages"

  if ! post_task_log_snapshot "$payload_file" "$tmpdir"; then
    error "Log snapshot capture failed"
    return 1
  fi
}

main() {
  log "Shutting down AgentAPI"

  local agentapi_pid=
  if [[ -n $PID_FILE_PATH ]]; then
    agentapi_pid=$(cat "$PID_FILE_PATH" 2> /dev/null || echo "")
  fi

  # State persistence is only enabled when the binary supports it (>= v0.12.0).
  # The default SIGUSR1 disposition on Linux is terminate, so sending it to an
  # older binary would kill the process.
  local state_persistence=0
  if [[ $ENABLE_STATE_PERSISTENCE == true ]] && version_at_least 0.12.0 "$(agentapi_version)"; then
    state_persistence=1
  fi

  # Trigger state save via SIGUSR1 (saves without exiting).
  if ((state_persistence)) && [[ -n $agentapi_pid ]] && kill -0 "$agentapi_pid" 2> /dev/null; then
    log "Sending SIGUSR1 to AgentAPI (pid $agentapi_pid) to save state"
    kill -USR1 "$agentapi_pid" || true
    # Allow time for state save to complete before proceeding.
    sleep 1
  fi

  # Capture log snapshot for task history.
  if [[ $TASK_LOG_SNAPSHOT == true ]]; then
    # Subshell scopes the EXIT trap (tmpdir cleanup) inside
    # capture_task_log_snapshot and preserves set -e, which
    # || would otherwise disable for the function body.
    (capture_task_log_snapshot) || log "Log snapshot capture failed, continuing shutdown"
  else
    log "Log snapshot disabled, skipping"
  fi

  # Graceful termination.
  if [[ -n $agentapi_pid ]] && kill -0 "$agentapi_pid" 2> /dev/null; then
    log "Sending SIGTERM to AgentAPI (pid $agentapi_pid)"
    kill -TERM "$agentapi_pid" 2> /dev/null || true

    # Wait for process to exit to guarantee a clean shutdown.
    local elapsed=0
    while kill -0 "$agentapi_pid" 2> /dev/null; do
      sleep 1
      ((elapsed++)) || true
      if ((elapsed % 5 == 0)); then
        log "Warning: AgentAPI (pid $agentapi_pid) still running after ${elapsed}s"
      fi
    done
  fi

  log "Shutdown complete"
}

main "$@"
