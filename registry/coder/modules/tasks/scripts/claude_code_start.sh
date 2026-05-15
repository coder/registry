#!/bin/bash

set -euo pipefail

ARG_CLAUDE_BINARY_PATH=${CLAUDE_CODE_ARG_CLAUDE_BINARY_PATH:-"${HOME}/.local/bin"}
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH/#\~/${HOME}}"
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH//\$HOME/${HOME}}"

export PATH="${ARG_CLAUDE_BINARY_PATH}:${PATH}"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_RESUME_SESSION_ID=${CLAUDE_CODE_ARG_RESUME_SESSION_ID:-}
ARG_CONTINUE=${CLAUDE_CODE_ARG_CONTINUE:-false}
ARG_DANGEROUSLY_SKIP_PERMISSIONS=${CLAUDE_CODE_ARG_DANGEROUSLY_SKIP_PERMISSIONS:-}
ARG_PERMISSION_MODE=${CLAUDE_CODE_ARG_PERMISSION_MODE:-}
ARG_WORKDIR=${CLAUDE_CODE_ARG_WORKDIR:-"${HOME}"}
ARG_AI_PROMPT=$(echo -n "${CLAUDE_CODE_ARG_AI_PROMPT:-}" | base64 -d)
ARG_CODER_HOST=${CLAUDE_CODE_ARG_CODER_HOST:-}
ARG_ENABLE_BOUNDARY=${ARG_ENABLE_BOUNDARY:-false}
ARG_ENABLE_AGENTAPI=${ARG_ENABLE_AGENTAPI:-false}

echo "--------------------------------"

printf "ARG_RESUME: %s\n" "${ARG_RESUME_SESSION_ID}"
printf "ARG_CONTINUE: %s\n" "${ARG_CONTINUE}"
printf "ARG_DANGEROUSLY_SKIP_PERMISSIONS: %s\n" "${ARG_DANGEROUSLY_SKIP_PERMISSIONS}"
printf "ARG_PERMISSION_MODE: %s\n" "${ARG_PERMISSION_MODE}"
printf "ARG_AI_PROMPT: %s\n" "${ARG_AI_PROMPT}"
printf "ARG_WORKDIR: %s\n" "${ARG_WORKDIR}"
printf "ARG_ENABLE_BOUNDARY: %s\n" "${ARG_ENABLE_BOUNDARY}"
printf "ARG_ENABLE_AGENTAPI: %s\n" "${ARG_ENABLE_AGENTAPI}"
printf "ARG_CODER_HOST: %s\n" "${ARG_CODER_HOST}"

echo "--------------------------------"

function validate_claude_installation() {
  if command_exists claude; then
    printf "Claude Code is installed\n"
  else
    printf "Error: Claude Code is not installed. Please enable install_claude_code or install it manually\n"
    exit 1
  fi
}

# Hardcoded task session ID for Coder task reporting
# This ensures all task sessions use a consistent, predictable ID
TASK_SESSION_ID="cd32e253-ca16-4fd3-9825-d837e74ae3c2"

get_project_dir() {
  local workdir_normalized
  workdir_normalized=$(echo "${ARG_WORKDIR}" | tr '/._' '-')
  echo "${HOME}/.claude/projects/${workdir_normalized}"
}

get_task_session_file() {
  echo "$(get_project_dir)/${TASK_SESSION_ID}.jsonl"
}

task_session_exists() {
  local session_file
  session_file=$(get_task_session_file)

  if [ -f "$session_file" ]; then
    printf "Task session file found: %s\n" "$session_file"
    return 0
  else
    printf "Task session file not found: %s\n" "$session_file"
    return 1
  fi
}

is_valid_session() {
  local session_file="$1"

  # Check if file exists and is not empty
  # Empty files indicate the session was created but never used so they need to be removed
  if [ ! -f "$session_file" ]; then
    printf "Session validation failed: file does not exist\n"
    return 1
  fi

  if [ ! -s "$session_file" ]; then
    printf "Session validation failed: file is empty, removing stale file\n"
    rm -f "$session_file"
    return 1
  fi

  # Check for minimum session content
  # Valid sessions need at least 2 lines: initial message and first response
  local line_count
  line_count=$(wc -l < "$session_file")
  if [ "$line_count" -lt 2 ]; then
    printf "Session validation failed: incomplete (only %s lines), removing incomplete file\n" "$line_count"
    rm -f "$session_file"
    return 1
  fi

  # Validate JSONL format by checking first 3 lines
  # Claude session files use JSONL (JSON Lines) format where each line is valid JSON
  if ! head -3 "$session_file" | jq empty 2> /dev/null; then
    printf "Session validation failed: invalid JSONL format, removing corrupt file\n"
    rm -f "$session_file"
    return 1
  fi

  # Verify the session has a valid sessionId field
  # This ensures the file structure matches Claude's session format
  if ! grep -q '"sessionId"' "$session_file" \
    || ! grep -m 1 '"sessionId"' "$session_file" | jq -e '.sessionId' > /dev/null 2>&1; then
    printf "Session validation failed: no valid sessionId found, removing malformed file\n"
    rm -f "$session_file"
    return 1
  fi

  printf "Session validation passed: %s\n" "$session_file"
  return 0
}

has_any_sessions() {
  local project_dir
  project_dir=$(get_project_dir)

  if [ -d "$project_dir" ] && find "$project_dir" -maxdepth 1 -name "*.jsonl" -size +0c 2> /dev/null | grep -q .; then
    printf "Sessions found in: %s\n" "$project_dir"
    return 0
  else
    printf "No sessions found in: %s\n" "$project_dir"
    return 1
  fi
}

AGENTAPI_CMD=()
BOUNDARY_CMD=("${ARG_BOUNDARY_WRAPPER_PATH}" --)
AGENT_CMD=()

build_agentapi_cmd() {
  AGENTAPI_CMD=(agentapi server --type claude --term-width 67 --term-height 1190 --)
}

build_agent_cmd() {
  local args=()

  if [[ -n "${ARG_PERMISSION_MODE}" ]]; then
    args+=(--permission-mode "${ARG_PERMISSION_MODE}")
  fi

  if [[ -n "${ARG_RESUME_SESSION_ID}" ]]; then
    echo "Resuming specified session: ${ARG_RESUME_SESSION_ID}"
    args+=(--resume "${ARG_RESUME_SESSION_ID}")
    [[ "${ARG_DANGEROUSLY_SKIP_PERMISSIONS}" = "true" ]] && args+=(--dangerously-skip-permissions)

  elif [[ "${ARG_CONTINUE}" = "true" ]]; then

    local session_file
    session_file=$(get_task_session_file)

    if task_session_exists && is_valid_session "${session_file}"; then
      echo "Resuming task session: ${TASK_SESSION_ID}"
      args+=(--resume "${TASK_SESSION_ID}" --dangerously-skip-permissions)
    else
      echo "Starting new task session: ${TASK_SESSION_ID}"
      args+=(--session-id "${TASK_SESSION_ID}" --dangerously-skip-permissions)
      [[ -n "${ARG_AI_PROMPT}" ]] && args+=(-- "${ARG_AI_PROMPT}")
    fi

  else
    echo "Continue disabled, starting fresh session"
    [[ "${ARG_DANGEROUSLY_SKIP_PERMISSIONS}" = "true" ]] && args+=(--dangerously-skip-permissions)
    [[ -n "${ARG_AI_PROMPT}" ]] && args+=(-- "${ARG_AI_PROMPT}")
  fi

  AGENT_CMD=(claude "${args[@]}")
}

function start() {
  # For Task reporting
  export CODER_MCP_ALLOWED_TOOLS="coder_report_task"

  mkdir -p "${ARG_WORKDIR}"
  cd "${ARG_WORKDIR}"

  if [[ "${ARG_ENABLE_AGENTAPI}" == "true" ]]; then
    build_agentapi_cmd

  fi
  build_agent_cmd

  printf "Running claude code with args: %s\n" "$(printf '%q ' "${AGENT_CMD[@]}")"

  if [[ "${ARG_ENABLE_BOUNDARY}" = "true" ]]; then
    printf "Starting with coder boundary enabled\n"
    "${AGENTAPI_CMD[@]}" "" -- "${AGENT_CMD[@]}"
  else
    "${AGENTAPI_CMD[@]}" "${AGENT_CMD[@]}"
  fi
}

validate_claude_installation
start
