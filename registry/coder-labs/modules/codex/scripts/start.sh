#!/bin/bash

source "$HOME"/.bashrc
set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

printf "Version: %s\n" "$(codex --version)"
set -o nounset
ARG_CODEX_TASK_PROMPT=$(echo -n "$ARG_CODEX_TASK_PROMPT" | base64 -d)
ARG_CONTINUE=${ARG_CONTINUE:-true}

echo "=== Codex Launch Configuration ==="
printf "OpenAI API Key: %s\n" "$([ -n "$ARG_OPENAI_API_KEY" ] && echo "Provided" || echo "Not provided")"
printf "Codex Model: %s\n" "${ARG_CODEX_MODEL:-"Default"}"
printf "Start Directory: %s\n" "$ARG_CODEX_START_DIRECTORY"
printf "Has Task Prompt: %s\n" "$([ -n "$ARG_CODEX_TASK_PROMPT" ] && echo "Yes" || echo "No")"
printf "Report Tasks: %s\n" "$ARG_REPORT_TASKS"
printf "Continue Sessions: %s\n" "$ARG_CONTINUE"
echo "======================================"
set +o nounset

SESSION_TRACKING_FILE="$HOME/.codex-module/.codex-task-session"

find_session_for_directory() {
  local target_dir="$1"

  if [ ! -f "$SESSION_TRACKING_FILE" ]; then
    return 1
  fi

  local session_id
  session_id=$(grep "^$target_dir|" "$SESSION_TRACKING_FILE" | cut -d'|' -f2 | head -1)

  if [ -n "$session_id" ]; then
    echo "$session_id"
    return 0
  fi

  return 1
}

store_session_mapping() {
  local dir="$1"
  local session_id="$2"

  mkdir -p "$(dirname "$SESSION_TRACKING_FILE")"

  if [ -f "$SESSION_TRACKING_FILE" ]; then
    grep -v "^$dir|" "$SESSION_TRACKING_FILE" > "$SESSION_TRACKING_FILE.tmp" 2> /dev/null || true
    mv "$SESSION_TRACKING_FILE.tmp" "$SESSION_TRACKING_FILE"
  fi

  echo "$dir|$session_id" >> "$SESSION_TRACKING_FILE"
}

find_recent_session_file() {
  local target_dir="$1"
  local sessions_dir="$HOME/.codex/sessions"

  if [ ! -d "$sessions_dir" ]; then
    return 1
  fi

  local latest_file=""
  local latest_time=0

  while IFS= read -r session_file; do
    local file_time
    file_time=$(stat -c %Y "$session_file" 2> /dev/null || stat -f %m "$session_file" 2> /dev/null || echo "0")
    local first_line
    first_line=$(head -n 1 "$session_file" 2> /dev/null)
    local session_cwd
    session_cwd=$(echo "$first_line" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)

    if [ "$session_cwd" = "$target_dir" ] && [ "$file_time" -gt "$latest_time" ]; then
      latest_file="$session_file"
      latest_time="$file_time"
    fi
  done < <(find "$sessions_dir" -type f -name "*.jsonl" 2> /dev/null)

  if [ -n "$latest_file" ]; then
    local first_line
    first_line=$(head -n 1 "$latest_file")
    local session_id
    session_id=$(echo "$first_line" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$session_id" ]; then
      echo "$session_id"
      return 0
    fi
  fi

  return 1
}

wait_for_session_file() {
  local target_dir="$1"
  local max_attempts=20
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    local session_id
    session_id=$(find_recent_session_file "$target_dir" 2> /dev/null || echo "")
    if [ -n "$session_id" ]; then
      echo "$session_id"
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  return 1
}

validate_codex_installation() {
  if command_exists codex; then
    printf "Codex is installed\n"
  else
    printf "Error: Codex is not installed. Please enable install_codex or install it manually\n"
    exit 1
  fi
}

setup_workdir() {
  if [ -d "${ARG_CODEX_START_DIRECTORY}" ]; then
    printf "Directory '%s' exists. Changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
    cd "${ARG_CODEX_START_DIRECTORY}" || {
      printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
      exit 1
    }
  else
    printf "Directory '%s' does not exist. Creating and changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
    mkdir -p "${ARG_CODEX_START_DIRECTORY}" || {
      printf "Error: Could not create directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
      exit 1
    }
    cd "${ARG_CODEX_START_DIRECTORY}" || {
      printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
      exit 1
    }
  fi
}

build_codex_args() {
  CODEX_ARGS=()

  if [ -n "$ARG_CODEX_MODEL" ]; then
    CODEX_ARGS+=("--model" "$ARG_CODEX_MODEL")
  fi

  if [ "$ARG_CONTINUE" = "true" ]; then
    existing_session=$(find_session_for_directory "$ARG_CODEX_START_DIRECTORY" 2> /dev/null || echo "")

    if [ -n "$existing_session" ]; then
      printf "Found existing task session for this directory: %s\n" "$existing_session"
      printf "Resuming existing session...\n"
      CODEX_ARGS+=("resume" "$existing_session")
    else
      printf "No existing task session found for this directory\n"
      printf "Starting new task session...\n"

      if [ -n "$ARG_CODEX_TASK_PROMPT" ]; then
        if [ "${ARG_REPORT_TASKS}" == "true" ]; then
          PROMPT="Complete the task at hand in one go. Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_CODEX_TASK_PROMPT"
        else
          PROMPT="Your task at hand: $ARG_CODEX_TASK_PROMPT"
        fi
        CODEX_ARGS+=("$PROMPT")
      fi
    fi
  else
    printf "Continue disabled, starting fresh session\n"

    if [ -n "$ARG_CODEX_TASK_PROMPT" ]; then
      if [ "${ARG_REPORT_TASKS}" == "true" ]; then
        PROMPT="Complete the task at hand in one go. Every step of the way, report your progress using Coder.coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_CODEX_TASK_PROMPT"
      else
        PROMPT="Your task at hand: $ARG_CODEX_TASK_PROMPT"
      fi
      CODEX_ARGS+=("$PROMPT")
    fi
  fi
}

capture_session_id() {
  if [ "$ARG_CONTINUE" = "true" ] && [ -z "$existing_session" ]; then
    printf "Capturing new session ID...\n"
    new_session=$(wait_for_session_file "$ARG_CODEX_START_DIRECTORY" || echo "")

    if [ -n "$new_session" ]; then
      store_session_mapping "$ARG_CODEX_START_DIRECTORY" "$new_session"
      printf "✓ Session tracked: %s\n" "$new_session"
      printf "This session will be automatically resumed on next restart\n"
    else
      printf "⚠ Could not capture session ID after 10s timeout\n"
    fi
  fi
}

start_codex() {
  printf "Starting Codex with arguments: %s\n" "${CODEX_ARGS[*]}"
  agentapi server --term-width 67 --term-height 1190 -- codex "${CODEX_ARGS[@]}" &
  capture_session_id
}

validate_codex_installation
setup_workdir
build_codex_args
start_codex
