# Common helpers for the Railway GraphQL provisioner scripts.
# Source this file with: . "$(dirname "$0")/lib.sh"
#
# Required env vars set by the caller (TF environment {} block):
#   API   - Railway GraphQL endpoint
#   TOKEN - Railway API token (Bearer)
# Optional:
#   PROJECT_NAME - Railway project name (used by lookup helpers)
#   STATE_DIR    - Local state directory holding *_id files

# Send a GraphQL query/mutation. The query string is embedded inside a
# JSON envelope via a temp file so we never need to shell-escape it.
# Stdout is the response body. Caller decides how to parse.
gql() {
  local query="$1"
  local tmpjson
  tmpjson=$(mktemp)
  printf '{"query": "%s"}' "$query" > "$tmpjson"
  curl -s --max-time 120 -X POST "$API" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d @"$tmpjson"
  local rc=$?
  rm -f "$tmpjson"
  return $rc
}

# Lookup project id + first environment id by $PROJECT_NAME. Prints
# "<project_id> <env_id>" on success, empty on miss. Always returns 0.
lookup_project_and_env() {
  local resp pid env_id
  resp=$(gql '{ projects { edges { node { id name environments { edges { node { id name } } } } } } }' || echo '')
  pid=$(echo "$resp" | grep -o '"id":"[^"]*","name":"'"$PROJECT_NAME"'"' \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
  if [ -z "$pid" ]; then return 0; fi
  env_id=$(echo "$resp" | sed 's/.*"id":"'"$pid"'","name":"'"$PROJECT_NAME"'","environments":{"edges":\[{"node":{"id":"\([^"]*\)".*/\1/' | head -1 || true)
  # Detect "no replacement" case: sed prints the input unchanged. Falls
  # back to a coarser grep that picks the first environment id seen.
  if [ "${#env_id}" -gt 100 ]; then
    env_id=$(echo "$resp" | grep -o '"environments":{"edges":\[{"node":{"id":"[^"]*"' \
      | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
  fi
  printf '%s %s\n' "$pid" "$env_id"
}

# Lookup project id only. Prints the id, empty on miss. Always returns 0.
lookup_project_id() {
  local resp
  resp=$(gql '{ projects { edges { node { id name } } } }' || echo '')
  echo "$resp" | grep -o '"id":"[^"]*","name":"'"$PROJECT_NAME"'"' \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true
}

# Lookup service id and env id inside a project. Args: project_id.
# Prints "<service_id> <env_id>". Service name fixed to "workspace",
# env name fixed to "production" to match the rest of the template.
lookup_service_and_env() {
  local pid="$1"
  local resp svc_id env_id
  resp=$(gql "{ project(id: \\\"$pid\\\") { services { edges { node { id name } } } environments { edges { node { id name } } } } }" || echo '')
  svc_id=$(echo "$resp" | grep -o '"id":"[^"]*","name":"workspace"' \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
  env_id=$(echo "$resp" | grep -o '"id":"[^"]*","name":"production"' \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
  printf '%s %s\n' "$svc_id" "$env_id"
}

# Load PROJECT_ID, SERVICE_ID, ENV_ID from $STATE_DIR if files exist.
# Sets the globals; never errors. Intended to be called before any
# fallback Railway API lookup.
load_state() {
  [ -n "${STATE_DIR:-}" ] || return 0
  [ -f "$STATE_DIR/project_id" ] && PROJECT_ID=$(cat "$STATE_DIR/project_id")
  [ -f "$STATE_DIR/service_id" ] && SERVICE_ID=$(cat "$STATE_DIR/service_id")
  [ -f "$STATE_DIR/environment_id" ] && ENV_ID=$(cat "$STATE_DIR/environment_id")
  return 0
}
