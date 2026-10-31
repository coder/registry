#!/usr/bin/env bash
# Shared utility functions for agentapi module scripts.

# version_at_least checks if an actual version meets a minimum requirement.
# Non-semver strings (e.g. "latest", custom builds) always pass.
# Usage: version_at_least <minimum> <actual>
#   version_at_least v0.12.0 v0.10.0  # returns 1 (false)
#   version_at_least v0.12.0 v0.12.0  # returns 0 (true)
#   version_at_least v0.12.0 latest   # returns 0 (true)
version_at_least() {
  local min="${1#v}"
  local actual="${2#v}"

  # Non-semver versions pass through (e.g. "latest", custom builds).
  if ! [[ $actual =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    return 0
  fi

  local act_major="${BASH_REMATCH[1]}"
  local act_minor="${BASH_REMATCH[2]}"
  local act_patch="${BASH_REMATCH[3]}"

  [[ $min =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 0

  local min_major="${BASH_REMATCH[1]}"
  local min_minor="${BASH_REMATCH[2]}"
  local min_patch="${BASH_REMATCH[3]}"

  # Arithmetic expressions set exit status: 0 (true) if non-zero, 1 (false) if zero.
  if ((act_major != min_major)); then
    ((act_major > min_major))
    return
  fi
  if ((act_minor != min_minor)); then
    ((act_minor > min_minor))
    return
  fi
  ((act_patch >= min_patch))
}

# agentapi_version returns the installed agentapi binary version (e.g. "0.11.8").
# Returns empty string if the binary is missing or doesn't support --version.
agentapi_version() {
  agentapi --version 2> /dev/null | awk '{print $NF}'
}
