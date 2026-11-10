terraform {
  required_providers {
    coder = {
      source = "coder/coder"
      # 2.20.0 adds coder_script_order, which orders the runner after setup.
      version = ">= 2.20.0"
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

# The repository a repo-scoped Cursor pool works on. The Cursor module
# declares agent_relay_cursor_repo_url, which Agent Relay stamps on every
# build, but a template cannot read a parameter a module declares, and Coder
# rejects a second parameter with the same name. So a repo-scoped pool sets
# this one too, through its template_parameters, to the same URL as its
# repo_url. Leave it empty for every other pool; Claude Code builds ignore it,
# because the Claude Code runner clones each session's repository itself.
data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository"
  description  = "Repository a repo-scoped Cursor pool clones before the worker starts. Agent Relay pools set this through template_parameters; leave it empty otherwise."
  type         = "string"
  default      = ""
  mutable      = true
}

# One prebuilt workspace per provider, so a session claims a running workspace
# instead of waiting for a cold start. Each session must be built within its
# pool's dispatch_deadline: by default 5 minutes from the work order for
# Claude Code and 10 minutes from the claim for Cursor, at most 15 for either.
#
# Each preset pins only self_hosted_provider. Coder hands a build a prebuild
# only when every preset parameter matches a value in the build request, and
# Agent Relay sends self_hosted_provider and its own parameters, nothing else.
# A preset that pinned any other parameter would never be claimed. Coder
# keeps prebuilds only for the active template version, so a pool that pins
# template_version never claims one.
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

  # Only a Cursor build clones; see data.coder_parameter.repo_url.
  repo_url  = local.self_hosted_provider == "cursor" ? data.coder_parameter.repo_url.value : ""
  clone_dir = "/home/coder/repo"

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

  # The Cursor worker registers the directory it starts in as the session's
  # repository, and a worker started outside the checkout registers as
  # "Repo: (repo unavailable)". The agent starts a command in dir only if it
  # exists, and in $HOME otherwise, so a Cursor pool with no repository still
  # starts in $HOME. coder_script_order.relay_runner below starts the worker
  # after the clone, so the directory exists by then. dir is deprecated, but it
  # is still the only way to set the worker's starting directory.
  #
  # dir is set on every Cursor build, whether or not repo_url is, because
  # changing it replaces the agent, and with it the pod or container: a
  # prebuild built without a repository would be replaced when a
  # repository-scoped session claims it. The preset fixes the provider, so dir
  # never changes on a claim.
  dir = local.self_hosted_provider == "cursor" ? local.clone_dir : null

  # Required. The key must stay agent_relay_status: Agent Relay reads it to
  # decide when to delete the workspace.
  metadata {
    key          = "agent_relay_status"
    display_name = local.self_hosted_provider == "cursor" ? "Worker" : "Session"
    script       = local.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  # Reports whether the runner holds a session, including between turns:
  # attached, unattached or stopped. Agent Relay extends the autostop deadline
  # while it reads a fresh `attached` sample, so keep the interval well under
  # two minutes. Without this item a live session is stopped at the TTL. Reads
  # the runner's local health endpoint, so the image needs curl (and awk for
  # Cursor).
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
# state. 1.x requires Coder 2.39.0 and Agent Relay v0.14.0 or newer; an older
# relay refuses this template with `missing parameter "agent_relay_credential"`.
# On an older deployment, pin 0.4.0 instead.
# https://registry.coder.com/modules/coder/agent-relay-claude-code
module "claude_code_runner" {
  count    = local.self_hosted_provider == "claude" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  # install_cli defaults to true, which downloads the CLI at start only when it
  # is not already on PATH, so it costs nothing on the default image. If you
  # run your own image with the CLI baked in, set install_cli = false so a
  # missing CLI fails fast instead of eating into the start deadline.
}

# Runs the Cursor worker and declares the parameters Agent Relay sets on each
# build. Like the Claude Code module, 1.x receives the session token as a
# workspace secret and has the same Coder and Agent Relay requirements. On an
# older deployment, pin 0.7.0 instead.
# https://registry.coder.com/modules/coder/agent-relay-cursor
module "cursor_worker" {
  count    = local.self_hosted_provider == "cursor" ? 1 : 0
  source   = "registry.coder.com/coder/agent-relay-cursor/coder"
  version  = "~> 1.0"
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

# Hands the repository URL to the setup script. A coder_env rather than the
# agent's env attribute, because changing that attribute on a claim would
# replace the agent; replacing a coder_env does not. An environment value rather
# than script text, so a quote in the URL cannot change what the script runs.
resource "coder_env" "setup_repo_url" {
  agent_id = coder_agent.main.id
  name     = "SETUP_REPO_URL"
  value    = local.repo_url
}

# Clones a repo-scoped Cursor pool's repository, over HTTPS with the owner's
# token from coder_external_auth.github. It exits 0 with nothing to do on every
# other build, including an unclaimed prebuild. A failed clone exits non-zero,
# so the ordering rule below skips the worker and Agent Relay fails the session
# instead of handing the developer a workspace with no repository.
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

    # A full clone: a shallow one is single-branch, so a session asked to work
    # on another branch would find nothing to check out.
    echo "Cloning $repo_url into $clone_dir."
    git clone -- "$repo_url" "$clone_dir"
  EOT
}

# Starts the runner only after the git identity is set and the setup script
# has finished, instead of as soon as the agent runs its start scripts. With
# the default requires = "success", a failed setup step skips the runner and
# Agent Relay fails the session: about a minute later from Agent Relay v0.16.0,
# after its startup grace before that.
#
# One rule names both runner modules. A module with count = 0 selects no
# scripts, and a rule with nothing to run adds no ordering, so only the
# instantiated runner is affected. The selectors are Terraform addresses that
# Coder resolves when the template is pushed; terraform validate does not check
# them. Ordering needs Coder 2.39.0 or newer; older Coder ignores the rule.
# https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/script_order
data "coder_script_order" "relay_runner" {
  rule {
    phase = "start"
    run   = ["module.claude_code_runner", "module.cursor_worker"]
    after = ["module.git-config", "coder_script.setup"]
  }
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
