terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces. A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspace pods in. It must exist before any workspace is created."
}

variable "image" {
  type        = string
  description = "Container image for workspaces. The default carries the Claude Code and Cursor CLIs."
  default     = "ghcr.io/coder/agent-relay-workspace:latest"
}

variable "cpu" {
  type        = string
  description = "CPU cores for each session pod."
  default     = "2"
}

variable "memory" {
  type        = string
  description = "Memory in GiB for each session pod."
  default     = "4"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
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

locals {
  self_hosted_provider = data.coder_parameter.self_hosted_provider.value

  # Indexed references keep the agent dependent on the output alone. A splat
  # would pull in the whole module, which depends on the agent.
  status_metadata_script = try(module.cursor_worker[0].status_metadata_script, module.claude_code_runner[0].status_metadata_script)
}

# Lets a session clone and push over HTTPS with the workspace owner's GitHub
# token through GIT_ASKPASS. Optional, because the relay builds without a human
# present and a prebuild owner can never link an account. Change the id to
# match the deployment's external auth provider.
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
}

# Sets user.name and user.email so a session can commit as the workspace owner.
module "git-config" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/git-config/coder"
  version            = "~> 1.0"
  agent_id           = coder_agent.main.id
  allow_email_change = true
}

# One pod per session, with no persistent volume: Agent Relay deletes the
# workspace when the runner exits, so a volume would outlive its session.
resource "kubernetes_pod_v1" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    # A crashed runner fails the session visibly instead of restarting.
    restart_policy = "Never"
    # Gives the runner modules' stop scripts time to shut the runner down.
    termination_grace_period_seconds = 30

    container {
      name    = "dev"
      image   = var.image
      command = ["sh", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          "cpu"    = var.cpu
          "memory" = "${var.memory}Gi"
        }
        limits = {
          "cpu"    = var.cpu
          "memory" = "${var.memory}Gi"
        }
      }
    }
  }
}
