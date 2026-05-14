terraform {
  required_version = ">= 1.5"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "workspace_id" {
  type        = string
  description = "data.coder_workspace.me.id from the parent template. Used by the supervisor to self-evict via the workspace builds endpoint."
}

variable "pool_secret" {
  type        = string
  description = "Claude Code self-hosted runner pool secret (from claude.ai)."
  sensitive   = true
}

variable "self_evict_token" {
  type        = string
  description = "Per-workspace, scope-restricted Coder API token. Scope = workspace:delete + workspace:read + template:read + user:read, allow_list = this workspace's UUID. A leaked copy can only delete this one workspace. The parent template mints it via the Mastercard/restapi provider at build time."
  sensitive   = true
}

variable "git_bot_token" {
  type        = string
  description = "Optional git PAT for the bot identity. Wired through GIT_ASKPASS so the runner's child claude can push without baking credentials into the image."
  sensitive   = true
  default     = ""
}

variable "capacity" {
  type        = number
  description = "Maximum sessions the runner serves at once. The runner locks to one Anthropic user; this caps parallelism within that user's queue."
  default     = 4
  validation {
    condition     = var.capacity >= 1 && var.capacity <= 16
    error_message = "capacity must be between 1 and 16."
  }
}

variable "runner_binary_path" {
  type        = string
  description = "Path to the `claude self-hosted-runner` binary inside the workspace."
  default     = "/usr/local/bin/claude"
}

variable "claude_binary_path" {
  type        = string
  description = "Path to the Claude Code binary the wrapper execs for each session."
  default     = "/opt/claude/claude"
}

variable "order" {
  type        = number
  description = "Order of the runner script in the agent UI."
  default     = null
}

resource "coder_env" "pool_secret" {
  agent_id = var.agent_id
  name     = "CLAUDE_POOL_SECRET"
  value    = var.pool_secret
}

resource "coder_env" "capacity" {
  agent_id = var.agent_id
  name     = "CLAUDE_CAPACITY"
  value    = tostring(var.capacity)
}

resource "coder_env" "git_bot_token" {
  agent_id = var.agent_id
  name     = "GIT_BOT_TOKEN"
  value    = var.git_bot_token
}

resource "coder_env" "self_token" {
  agent_id = var.agent_id
  name     = "CODER_SELF_TOKEN"
  value    = var.self_evict_token
}

resource "coder_env" "workspace_id" {
  agent_id = var.agent_id
  name     = "CODER_WORKSPACE_ID"
  value    = var.workspace_id
}

resource "coder_script" "claude_runner" {
  agent_id           = var.agent_id
  display_name       = "Claude self-hosted runner"
  icon               = "/icon/code.svg"
  run_on_start       = true
  start_blocks_login = false
  script = templatefile("${path.module}/scripts/run.sh", {
    CLAUDE_BINARY_PATH = var.claude_binary_path
    RUNNER_BINARY_PATH = var.runner_binary_path
  })
}

# Agent metadata items. The parent splats this list into a
# `dynamic "metadata"` block on its own `coder_agent` because nested
# blocks cannot be injected from a module. Scraped from the runner's
# local /healthz and /metrics endpoints; this is the only window a
# Coder admin has into who the Anthropic pool has bound this workspace
# to (the runner does not expose the locked user's email over its
# local endpoints; that lives in claude.ai > Self-hosted runner pools).
output "agent_metadata" {
  description = "List of agent metadata items the parent template should splat into a `dynamic \"metadata\"` block on its coder_agent."
  value = [
    {
      display_name = "Lock status"
      key          = "0_lock_status"
      interval     = 10
      timeout      = 5
      script       = <<-EOT
        val=$(curl -fsS http://127.0.0.1:8080/metrics 2>/dev/null \
          | awk '/^claude_code_self_hosted_runner_locked_account[[:space:]]/ {print $2; exit}')
        if [ "$val" = "1" ]; then
          printf 'locked'
        else
          printf 'unlocked'
        fi
      EOT
    },
    {
      display_name = "Active sessions"
      key          = "1_active_sessions"
      interval     = 5
      timeout      = 5
      script       = <<-EOT
        active=$(curl -fsS http://127.0.0.1:8080/healthz 2>/dev/null \
          | jq -r '.active_sessions // empty')
        if [ -z "$active" ]; then echo '?'; exit 0; fi
        printf '%s / %s' "$active" "$${CLAUDE_CAPACITY:-1}"
      EOT
    },
    {
      display_name = "Runner ID"
      key          = "2_runner_id"
      interval     = 30
      timeout      = 5
      script       = <<-EOT
        curl -fsS http://127.0.0.1:8080/healthz 2>/dev/null \
          | jq -r '.runner_id // "(starting)"'
      EOT
    },
    {
      display_name = "Last Anthropic poll"
      key          = "3_last_poll"
      interval     = 15
      timeout      = 5
      script       = <<-EOT
        age=$(curl -fsS http://127.0.0.1:8080/healthz 2>/dev/null \
          | jq -r '.last_poll_age_ms // empty')
        if [ -z "$age" ]; then echo '?'; exit 0; fi
        if [ "$age" -lt 30000 ]; then
          printf 'ok (%sms ago)' "$age"
        else
          printf 'stale (%ss ago)' $((age/1000))
        fi
      EOT
    },
  ]
}
