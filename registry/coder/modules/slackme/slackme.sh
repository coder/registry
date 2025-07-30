#!/usr/bin/env sh

PROVIDER_ID=${PROVIDER_ID}
SLACK_MESSAGE=$(
  cat << "EOF"
${SLACK_MESSAGE}
EOF
)
SLACK_URL=$${SLACK_URL:-https://slack.com}

usage() {
  cat << EOF
slackme — Send a Slack notification when a command finishes
Usage: slackme <command>

Example: slackme npm run long-build
EOF
}

pretty_duration() {
  local duration_ms=$1

  # If the duration is less than 1 second, display in milliseconds
  if [ $duration_ms -lt 1000 ]; then
    echo "$${duration_ms}ms"
    return
  fi

  # Convert the duration to seconds
  local duration_sec=$((duration_ms / 1000))
  local remaining_ms=$((duration_ms % 1000))

  # If the duration is less than 1 minute, display in seconds (with ms)
  if [ $duration_sec -lt 60 ]; then
    echo "$${duration_sec}.$${remaining_ms}s"
    return
  fi

  # Convert the duration to minutes
  local duration_min=$((duration_sec / 60))
  local remaining_sec=$((duration_sec % 60))

  # If the duration is less than 1 hour, display in minutes and seconds
  if [ $duration_min -lt 60 ]; then
    echo "$${duration_min}m $${remaining_sec}.$${remaining_ms}s"
    return
  fi

  # Convert the duration to hours
  local duration_hr=$((duration_min / 60))
  local remaining_min=$((duration_min % 60))

  # Display in hours, minutes, and seconds
  echo "$${duration_hr}hr $${remaining_min}m $${remaining_sec}.$${remaining_ms}s"
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

BOT_TOKEN=$(coder external-auth access-token $PROVIDER_ID)
if [ $? -ne 0 ]; then
  printf "Authenticate with Slack to be notified when a command finishes:\n$BOT_TOKEN\n"
  exit 1
fi

USER_ID=$(coder external-auth access-token $PROVIDER_ID --extra "authed_user.id")
if [ $? -ne 0 ]; then
  printf "Failed to get authenticated user ID:\n$USER_ID\n"
  exit 1
fi

START=$(date +%s%N)
# Run all arguments as a command
$@
END=$(date +%s%N)
DURATION_MS=$${DURATION_MS:-$(((END - START) / 1000000))}
PRETTY_DURATION=$(pretty_duration $DURATION_MS)

set -e
COMMAND=$(echo $@)
SLACK_MESSAGE=$(echo "$SLACK_MESSAGE" | sed "s|\\$COMMAND|$COMMAND|g")
SLACK_MESSAGE=$(echo "$SLACK_MESSAGE" | sed "s|\\$DURATION|$PRETTY_DURATION|g")

curl --silent -o /dev/null --header "Authorization: Bearer $BOT_TOKEN" \
  -G --data-urlencode "text=$${SLACK_MESSAGE}" \
  "$SLACK_URL/api/chat.postMessage?channel=$USER_ID&pretty=1"
