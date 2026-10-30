terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "image" {
  type        = string
  description = "Container image for workspaces. The default carries the Claude Code and Cursor CLIs."
  default     = "ghcr.io/coder/agent-relay-workspace:latest"
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Each Agent Relay pool stamps this through its template_parameters, so one
# template serves both providers. Only the selected runner module is
# instantiated, which keeps the other module's parameters off the build.
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

# One prebuilt workspace per provider, so a session claims a running workspace
# instead of waiting for a cold start. A Claude Code session must start within
# 300 seconds of its work order, and a Cursor session within the pool's
# dispatch deadline.
#
# Each preset pins only self_hosted_provider. Coder hands a build a prebuild
# only when every preset parameter matches a value in the build request, and
# Agent Relay sends self_hosted_provider and its own parameters, nothing else.
# A preset that pinned any other parameter would never be claimed.
#
# A prebuild has no work order, so its runner idles until a claim rebuilds it
# with the relay's parameters and the agent restarts the runner module's
# scripts.
#
# Size instances to how many sessions start at once. Each instance is a
# workspace running continuously, and once every prebuild is claimed, new
# sessions build cold until Coder replaces them. Prebuild jobs also need
# provisioners and compete with session builds for the queue; where possible,
# route them to dedicated provisioners with the is_prebuild tag.
data "coder_workspace_preset" "claude" {
  name        = "Claude Code"
  description = "Prebuilt Claude Code runner."
  icon        = "/icon/claude.svg"
  parameters = {
    (data.coder_parameter.self_hosted_provider.name) = "claude"
  }
  prebuilds {
    instances = 1
    # Replace an unclaimed prebuild hourly, so a session does not start on an
    # image tag that has moved since.
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
    instances = 1
    expiration_policy {
      ttl = 3600
    }
  }
}

locals {
  self_hosted_provider = data.coder_parameter.self_hosted_provider.value

  # Indexed references keep the agent dependent on the output alone. A splat
  # would pull in the whole module, which depends on the agent.
  status_metadata_script           = try(module.cursor_worker[0].status_metadata_script, module.claude_code_runner[0].status_metadata_script)
  session_attached_metadata_script = try(module.cursor_worker[0].session_attached_metadata_script, module.claude_code_runner[0].session_attached_metadata_script)
}

# Lets a session clone and push over HTTPS with the workspace owner's GitHub
# token through GIT_ASKPASS. Change the id to match the deployment's external
# auth provider.
#
# optional = true is required, not a convenience. Prebuilds are created by a
# system user that can never link an account, so a required provider stops
# them from provisioning, and the relay builds with no person present to link
# one either.
data "coder_external_auth" "github" {
  id       = "github"
  optional = true
}

resource "coder_agent" "main" {
  # The default image is published for amd64 only.
  arch = "amd64"
  os   = "linux"

  # Required. The key must stay agent_relay_status: Agent Relay reads it to
  # decide when to delete the workspace.
  metadata {
    key          = "agent_relay_status"
    display_name = local.self_hosted_provider == "cursor" ? "Worker" : "Session"
    script       = local.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  # Optional. Reports whether the runner holds a session, including between
  # turns: attached, unattached or stopped. Reads the runner's local health
  # endpoint, so the image needs curl (and awk for Cursor).
  metadata {
    key          = "agent_relay_session_attached"
    display_name = "Session attached"
    script       = local.session_attached_metadata_script
    interval     = 30
    timeout      = 5
  }
}

# Runs the Claude Code self-hosted runner and declares the parameters Agent
# Relay sets on each build. Since 1.0.0 the work order arrives as an ephemeral
# workspace secret, so it never appears in build parameters or Terraform
# state. 1.0.0 requires Coder 2.39.0 and Agent Relay v0.14.0 or newer; an older
# relay refuses this template with `missing parameter "agent_relay_credential"`.
# On an older deployment, pin 0.4.0 instead.
# https://registry.coder.com/modules/coder/agent-relay-claude-code
module "claude_code_runner" {
  count    = local.self_hosted_provider == "claude" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  # install_cli defaults to true, which downloads the CLI at start only when it
  # is not already on PATH, so it costs nothing on the default image. If you
  # run your own image with the CLI baked in, set install_cli = false so a
  # missing CLI fails fast instead of eating into the start deadline.
}

# Runs the Cursor worker and declares the parameters Agent Relay sets on each
# build. Like the Claude Code module, 1.0.0 receives the session token as a
# workspace secret and has the same Coder and Agent Relay requirements. On an
# older deployment, pin 0.7.0 instead.
# https://registry.coder.com/modules/coder/agent-relay-cursor
module "cursor_worker" {
  count    = local.self_hosted_provider == "cursor" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-cursor/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  # install_cli defaults to true, which downloads the CLI at start only when it
  # is not already on PATH, so it costs nothing on the default image. If you
  # run your own image with the CLI baked in, set install_cli = false so a
  # missing CLI fails fast instead of eating into the start deadline.
}

# Sets user.name and user.email so a session can commit as the workspace owner.
module "git-config" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/git-config/coder"
  version            = "~> 1.0"
  agent_id           = coder_agent.main.id
  allow_email_change = true
}

# One container per session, with no volume: Agent Relay deletes the workspace
# when the runner exits, so a volume would outlive its session.
#
# Claiming a prebuild re-applies this with a new owner and workspace name, and
# Docker replaces a container whose name, hostname or labels change, which
# would cost the claim the cold start the prebuild exists to avoid. So unlike
# the docker template, everything here is keyed on the workspace ID, which a
# claim keeps; look the owner up from the ID. The agent token is reused across
# a claim, so the env does not change either.
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = var.image
  name  = "coder-${data.coder_workspace.me.id}"
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Gives the runner modules' stop scripts time to shut the runner down.
  stop_timeout          = 30
  destroy_grace_seconds = 30

  # Add a label in Docker to keep track of orphan resources.
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
