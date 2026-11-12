terraform {
  required_providers {
    coder = {
      source = "coder/coder"
      # 2.20.0 adds coder_script_order.
      version = ">= 2.20.0"
    }
    docker = {
      source = "kreuzwerker/docker"
      # 3.6.0 applies cpu_period and cpu_quota.
      version = ">= 3.6.0"
    }
  }
}

provider "coder" {}

variable "docker_socket" {
  description = "(Optional) Docker socket URI"
  type        = string
  default     = ""
}

variable "image" {
  description = "Container image for workspaces. The default carries the Claude Code and Cursor CLIs."
  type        = string
  default     = "ghcr.io/coder/agent-relay-workspace:latest"
}

variable "cpu" {
  description = "CPU cores for each session container. Fractions such as 0.5 are allowed."
  type        = number
  default     = 2

  validation {
    condition     = var.cpu >= 0.01
    error_message = "cpu must be at least 0.01."
  }
}

variable "memory" {
  description = "Memory in GiB for each session container. Fractions such as 0.5 are allowed."
  type        = number
  default     = 4

  validation {
    condition     = var.memory > 0
    error_message = "memory must be greater than 0."
  }
}

variable "claude_code_prebuilds" {
  description = "Prebuilt Claude Code workspaces to keep ready. Set 0 if no Claude Code pool uses this template."
  type        = number
  default     = 1

  validation {
    condition     = var.claude_code_prebuilds >= 0 && floor(var.claude_code_prebuilds) == var.claude_code_prebuilds
    error_message = "claude_code_prebuilds must be a whole number of at least 0."
  }
}

variable "cursor_prebuilds" {
  description = "Prebuilt Cursor workspaces to keep ready. Set 0 if no Cursor pool uses this template."
  type        = number
  default     = 1

  validation {
    condition     = var.cursor_prebuilds >= 0 && floor(var.cursor_prebuilds) == var.cursor_prebuilds
    error_message = "cursor_prebuilds must be a whole number of at least 0."
  }
}

provider "docker" {
  # An empty socket uses the provider's default host.
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Set by each Agent Relay pool through template_parameters; only the selected
# runner module is instantiated.
#
# Keep the default. Without a value, Coder's dynamic parameter evaluation,
# which Agent Relay uses to validate pools, instantiates both modules and
# reports their shared parameters as duplicates. A Cursor pool that omits it
# still fails validation: it evaluates as Claude Code, which lacks the Cursor
# parameters.
data "coder_parameter" "self_hosted_provider" {
  name         = "self_hosted_provider"
  display_name = "Self-hosted provider"
  description  = "Which Agent Relay runner this workspace serves. Agent Relay pools set this through template_parameters."
  type         = "string"
  default      = "claude"
  mutable      = false

  option {
    name  = "Claude Code"
    value = "claude"
    icon  = "/icon/claude.svg"
  }
  option {
    name  = "Cursor"
    value = "cursor"
    icon  = "/icon/cursor.svg"
  }
}

# Clone target for a repo-scoped Cursor pool, set to the same URL as the pool's
# repo_url. The template cannot read the Cursor module's
# agent_relay_cursor_repo_url, and Coder rejects a second parameter with that
# name. Leave it empty for other pools; Claude Code builds ignore it.
data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository"
  description  = "Repository a repo-scoped Cursor pool clones before the worker starts. Agent Relay pools set this through template_parameters; leave it empty otherwise."
  type         = "string"
  default      = ""
  mutable      = true
}

# Prebuilds let a session claim a running workspace instead of building cold,
# which eats into its pool's dispatch_deadline. Size each count to how many
# sessions start at once; every instance runs until claimed.
#
# Presets pin only self_hosted_provider: Coder hands out a prebuild only when
# every preset parameter matches the build request, and Agent Relay sends
# nothing else. Prebuilds exist only for the active version, so a pool that
# pins template_version always builds cold. A prebuild's runner idles until a
# claim rebuilds it with the relay's parameters.
#
# Prebuild jobs compete with session builds for provisioners; where possible,
# route them to dedicated ones with the is_prebuild tag.
data "coder_workspace_preset" "claude" {
  name        = "Claude Code"
  description = "Prebuilt Claude Code runner."
  icon        = "/icon/claude.svg"
  parameters = {
    (data.coder_parameter.self_hosted_provider.name) = "claude"
  }
  prebuilds {
    instances = var.claude_code_prebuilds
    # Hourly, so an unclaimed prebuild does not lag behind a moved image tag.
    expiration_policy {
      ttl = 3600
    }
  }
}

data "coder_workspace_preset" "cursor" {
  name        = "Cursor"
  description = "Prebuilt Cursor worker."
  icon        = "/icon/cursor.svg"
  parameters = {
    (data.coder_parameter.self_hosted_provider.name) = "cursor"
  }
  prebuilds {
    instances = var.cursor_prebuilds
    expiration_policy {
      ttl = 3600
    }
  }
}

locals {
  self_hosted_provider = data.coder_parameter.self_hosted_provider.value

  # Only a Cursor build clones; see data.coder_parameter.repo_url.
  repo_url  = local.self_hosted_provider == "cursor" ? data.coder_parameter.repo_url.value : ""
  clone_dir = "/home/coder/repo"

  # Indexed, not a splat: a splat depends on the whole module, which depends on
  # the agent.
  status_metadata_script           = try(module.cursor_worker[0].status_metadata_script, module.claude_code_runner[0].status_metadata_script)
  session_attached_metadata_script = try(module.cursor_worker[0].session_attached_metadata_script, module.claude_code_runner[0].session_attached_metadata_script)
}

# The owner's GitHub token for HTTPS clone and push. Match the id to your
# deployment's provider. optional = true is required: prebuilds and relay
# builds have no person present to link an account.
data "coder_external_auth" "github" {
  id       = "github"
  optional = true
}

resource "coder_agent" "main" {
  # The default image is published for amd64 only.
  arch = "amd64"
  os   = "linux"

  # The Cursor worker registers its start directory as the session's
  # repository. The agent uses $HOME while dir does not exist, and the ordering
  # rule starts the worker after the clone. Set on every Cursor build, with or
  # without repo_url, because changing dir replaces the agent and its Pod or
  # container, which would discard a prebuild claimed by a repo-scoped session.
  dir = local.self_hosted_provider == "cursor" ? local.clone_dir : null

  # Required. Agent Relay reads this key to decide when to delete the
  # workspace; do not rename it.
  metadata {
    key          = "agent_relay_status"
    display_name = local.self_hosted_provider == "cursor" ? "Worker" : "Session"
    script       = local.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  # Agent Relay extends autostop only while this reads a fresh `attached`, so
  # keep the interval well under two minutes. Needs curl, and awk for Cursor.
  metadata {
    key          = "agent_relay_session_attached"
    display_name = "Session attached"
    script       = local.session_attached_metadata_script
    interval     = 30
    timeout      = 5
  }

  # Dashboard only; Agent Relay ignores these.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

# 1.x takes the work order as an ephemeral workspace secret and needs Coder
# 2.39.0 and Agent Relay v0.14.0 or newer. On older deployments, pin 0.4.0.
# https://registry.coder.com/modules/coder/agent-relay-claude-code
module "claude_code_runner" {
  count    = local.self_hosted_provider == "claude" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  # install_cli (default true) downloads the CLI only when it is not on PATH.
  # With an image that bakes it in, set false so a missing CLI fails fast.
}

# Same 1.x requirements as the Claude Code module. On older deployments, pin
# 0.7.0.
# https://registry.coder.com/modules/coder/agent-relay-cursor
module "cursor_worker" {
  count    = local.self_hosted_provider == "cursor" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-cursor/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  # install_cli (default true) downloads the CLI only when it is not on PATH.
  # With an image that bakes it in, set false so a missing CLI fails fast.
}

# Sets user.name and user.email so a session can commit as the workspace owner.
module "git-config" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/git-config/coder"
  version            = "~> 1.0"
  agent_id           = coder_agent.main.id
  allow_email_change = true
}

# A coder_env, not the agent's env, so a URL set on a claim does not replace
# the agent. An environment value, not script text, so the URL cannot inject
# commands.
resource "coder_env" "setup_repo_url" {
  agent_id = coder_agent.main.id
  name     = "SETUP_REPO_URL"
  value    = local.repo_url
}

# Clones a repo-scoped Cursor pool's repository and exits 0 on every other
# build. A failed clone skips the worker, so Agent Relay fails the session
# instead of serving it without a repository.
resource "coder_script" "setup" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Workspace setup"
  icon         = "/icon/git.svg"
  run_on_start = true
  timeout      = 300
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    repo_url="$${SETUP_REPO_URL:-}"
    clone_dir="${local.clone_dir}"

    if [ -z "$repo_url" ]; then
      echo "No repository for this build; nothing to clone."
      exit 0
    fi
    if [ -d "$clone_dir/.git" ]; then
      echo "Repository already cloned into $clone_dir."
      exit 0
    fi

    # Full clone: a shallow one holds a single branch.
    echo "Cloning $repo_url into $clone_dir."
    git clone -- "$repo_url" "$clone_dir"
  EOT
}

# Starts the runner after git-config and setup succeed. A failed step skips the
# runner and Agent Relay fails the session, about a minute later from v0.16.0.
# A module with count = 0 selects nothing, so one rule serves both providers.
# Coder checks the selectors on push, not terraform validate; Coder older than
# 2.39.0 ignores the rule.
# https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/script_order
data "coder_script_order" "relay_runner" {
  rule {
    phase = "start"
    run   = ["module.claude_code_runner", "module.cursor_worker"]
    after = ["module.git-config", "coder_script.setup"]
  }
}

# One container per session, with no volume: Agent Relay deletes the workspace
# when the runner exits.
#
# A claim re-applies this with a new owner and workspace name, and Docker
# replaces a container whose name, hostname or labels change. So unlike the
# Docker Containers template, everything is keyed on the workspace ID, which a
# claim keeps. The agent token is reused across a claim, so env is stable too.
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = var.image
  name  = "coder-${data.coder_workspace.me.id}"
  # Use the Docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # Limits only; nothing is reserved. A CFS quota, not cpus: the provider reads
  # cpus back reformatted (2 as "2.0"), which would replace the container on a
  # claim. memory is in MiB.
  cpu_period = 100000
  cpu_quota  = floor(var.cpu * 100000)
  memory     = floor(var.memory * 1024)

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # A crashed runner fails the session instead of restarting.
  restart = "no"
  # Time for the runner's stop scripts.
  stop_timeout          = 30
  destroy_grace_seconds = 30

  # Tracks orphaned containers.
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
