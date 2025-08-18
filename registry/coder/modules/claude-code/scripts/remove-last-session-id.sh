# If lastSessionId is present in .claude.json, claude --continue will start a
# conversation starting from that session. The problem is that lastSessionId
# doesn't always point to the last session. The field is updated by claude only
# at the point of normal CLI exit. If Claude exits with an error, or if the user
# restarts the Coder workspace, lastSessionId will be stale, and claude --continue
# will start from an old session.
#
# If lastSessionId is missing, claude seems to accurately figure out where to
# start using the conversation history - even if the CLI previously exited with
# an error.
#
# This script removes the lastSessionId field from .claude.json.
if [ $# -eq 0 ]; then
  echo "No working directory provided - it must be the first argument"
  exit 1
fi

# Get absolute path of working directory
working_dir=$(realpath "$1")
echo "workingDir $working_dir"

# Path to .claude.json
claude_json_path="$HOME/.claude.json"
echo ".claude.json path $claude_json_path"

# Check if .claude.json exists
if [ ! -f "$claude_json_path" ]; then
  echo "No .claude.json file found"
  exit 0
fi

# Use jq to check if lastSessionId exists for the working directory and remove it

if jq -e ".projects[\"$working_dir\"].lastSessionId" "$claude_json_path" > /dev/null 2>&1; then
  # Remove lastSessionId and update the file
  jq "del(.projects[\"$working_dir\"].lastSessionId)" "$claude_json_path" > "${claude_json_path}.tmp" && mv "${claude_json_path}.tmp" "$claude_json_path"
  echo "Removed lastSessionId from .claude.json"
else
  echo "No lastSessionId found in .claude.json - nothing to do"
fi
