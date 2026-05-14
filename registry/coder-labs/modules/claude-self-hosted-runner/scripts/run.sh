#!/usr/bin/env bash
# Wires up everything the Claude Code self-hosted runner needs at agent
# start, then spawns a detached supervisor that keeps the runner alive
# and self-evicts on drain.
#
# Runtime env (set by coder_env in main.tf):
#   CLAUDE_POOL_SECRET   Anthropic pool secret (mandatory).
#   CLAUDE_CAPACITY      Max parallel sessions per runner (default 1).
#   GIT_BOT_TOKEN        Optional bot PAT for GIT_ASKPASS.
#   CODER_SELF_TOKEN     Per-workspace scope-restricted Coder API token.
#   CODER_WORKSPACE_ID   This workspace's UUID, used by self-eviction.
#   CODER_AGENT_URL      Set by the Coder agent itself.

set -euo pipefail

CLAUDE_BINARY_PATH='${CLAUDE_BINARY_PATH}'
RUNNER_BINARY_PATH='${RUNNER_BINARY_PATH}'

if [ -z "$${CLAUDE_POOL_SECRET:-}" ]; then
  echo "CLAUDE_POOL_SECRET is empty. Set the pool_secret input on the module."
  exit 1
fi

install -d -m 0700 "$HOME/.claude"

# --- Bot git askpass ----------------------------------------------------
if [ -n "$${GIT_BOT_TOKEN:-}" ]; then
  install -d -m 0700 "$HOME/.git-creds"
  cat > "$HOME/.git-creds/askpass.sh" << 'ASK'
#!/bin/sh
printf '%s' "$GIT_BOT_TOKEN"
ASK
  chmod 0500 "$HOME/.git-creds/askpass.sh"
  git config --global core.askPass "$HOME/.git-creds/askpass.sh"
  git config --global credential.helper ''
fi

# --- Host Docker socket gid fixup --------------------------------------
if [ -S /var/run/docker.sock ]; then
  sock_gid=$(stat -c %g /var/run/docker.sock)
  docker_gid=$(getent group docker | cut -d: -f3 || true)
  if [ -n "$${docker_gid:-}" ] && [ "$${sock_gid}" != "$${docker_gid}" ]; then
    sudo chgrp "$${docker_gid}" /var/run/docker.sock 2> /dev/null || true
  fi
fi

# --- Pool secret on disk -----------------------------------------------
POOL_SECRET_FILE="$HOME/.claude/pool-secret"
rm -f "$POOL_SECRET_FILE"
umask 077
printf '%s' "$${CLAUDE_POOL_SECRET}" > "$POOL_SECRET_FILE"
chmod 0400 "$POOL_SECRET_FILE"

# --- Wrapper script -----------------------------------------------------
# Runner execs this once per session, appending its server-computed
# flags. Claude Code's flag parser is last-occurrence-wins, so flags
# after "$@" win. Force --permission-mode bypassPermissions so
# unattended sessions never stall on a tool-approval prompt.
WRAPPER="$HOME/.claude/wrapper.sh"
{
  echo '#!/bin/bash'
  echo "exec $${CLAUDE_BINARY_PATH} \"\$@\" --permission-mode bypassPermissions"
} > "$WRAPPER"
chmod 0755 "$WRAPPER"

# --- Supervisor --------------------------------------------------------
# Runs the runner in the foreground; on runner exit POSTs a delete
# build to self-evict. Raw curl, not `coder delete`: the CLI fetches
# workspace resources first, which fails with the per-workspace
# scoped token whose allow-list excludes peer prebuilds.
#
# Single-quoted heredoc, so nothing is expanded by the outer shell.
# The supervisor reads its env vars (CODER_SELF_TOKEN, CODER_AGENT_URL,
# etc.) at runtime, when it's invoked under setsid.
SUPERVISOR="$HOME/.claude/supervisor.sh"
cat > "$SUPERVISOR" << SUP
#!/usr/bin/env bash
set -uo pipefail
exec >>"\$HOME/.claude/supervisor.log" 2>&1
echo "[supervisor] start \$(date -Is)"

$${RUNNER_BINARY_PATH} self-hosted-runner \\
  --pool-secret-file "\$HOME/.claude/pool-secret" \\
  --capacity        "\$${CLAUDE_CAPACITY:-1}" \\
  --log-file        "\$HOME/.claude/runner.log" \\
  --exec-path       "\$HOME/.claude/wrapper.sh"
echo "[supervisor] runner exited rc=\$? \$(date -Is)"

if [ -z "\$${CODER_SELF_TOKEN:-}" ]; then
  echo "[supervisor] CODER_SELF_TOKEN is empty; skipping self-eviction."
  exit 0
fi

http_code=\$(curl -s -o /tmp/evict.out -w "%%{http_code}" \\
  -X POST \\
  -H "Coder-Session-Token: \$CODER_SELF_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{"transition":"delete"}' \\
  "\$CODER_AGENT_URL/api/v2/workspaces/\$CODER_WORKSPACE_ID/builds")
if [ "\$http_code" = "201" ]; then
  echo "[supervisor] self-eviction queued (HTTP 201)."
else
  echo "[supervisor] self-eviction failed (HTTP \$http_code): \$(head -c 300 /tmp/evict.out)"
fi
SUP
chmod 0700 "$SUPERVISOR"

# Detach with setsid + nohup. The supervisor reopens stdout/stderr to
# its own logfile; redirect all standard fds here to /dev/null so this
# script's exit doesn't drag the supervisor with it.
setsid nohup "$SUPERVISOR" < /dev/null > /dev/null 2>&1 &
disown

echo "Runner spawned as detached supervisor (pid=$!). See ~/.claude/supervisor.log."
