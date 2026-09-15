# Claude Code self-hosted runner module for Coder templates.
#
# A BYOC-compatible template includes this module and passes it the
# workspace's coder_agent id. It declares every rich parameter
# Agent Relay stamps on a build and runs `claude self-hosted-runner`
# via a coder_script.
#
# Parameter contract (enforced by Agent Relay at startup via the dynamic
# parameters evaluate endpoint):
#
#   - agent_relay_session_id, agent_relay_delivery_id, agent_relay_pool are
#     persistent state: coderd only stores parameter values the
#     template declares, and Agent Relay's dedupe and reconciliation query
#     workspaces with `param:` search filters on them.
#   - agent_relay_credential, agent_relay_claude_code_lock_to_account,
#     and agent_relay_attempt are ephemeral runner inputs, reset
#     between builds. An ephemeral value is still recorded on the build
#     that set it, which is how Agent Relay reads the attempt back when
#     it reaps a dead workspace.
#
# The runner's lifecycle is published through the agent_relay_status agent
# metadata item, whose script this module renders. The script starts the
# runner detached and exits so the agent reaches the ready lifecycle
# state rather than sitting in starting for the whole session.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "ID of the coder_agent that should receive the runner env vars and run the runner script."
}

variable "cli_binary" {
  type        = string
  default     = "claude"
  description = "Path to the Claude Code CLI binary in the workspace image. Override to test a beta build."
}

variable "install_cli" {
  type        = bool
  default     = true
  description = "Install the Claude Code CLI (curl https://claude.ai/install.sh -fsSL | bash) when the workspace starts and the CLI is not already on PATH. Defaults to true so a template works against an image that has no CLI. A CLI already in the image is used as is and never upgraded, which is the recommended and fastest path: the download only runs when the binary is missing, and it spends part of the claim-to-ready window when it does."
}

variable "state_file" {
  type        = string
  default     = "/tmp/agent-relay/runner-state"
  description = "Path the runner supervisor writes its lifecycle state to, read by the agent_relay_status agent metadata item."
}

variable "log_file" {
  type        = string
  default     = "/tmp/agent-relay/runner.log"
  description = "Path the detached runner's output is written to."
}

variable "serving_log_pattern" {
  type        = string
  default     = "Picked up session"
  description = "Runner log substring that means a session was claimed. Only distinguishes the agent_relay_status values working and serving; a stale pattern degrades to working and affects nothing else."
}

data "coder_parameter" "agent_relay_session_id" {
  name         = "agent_relay_session_id"
  display_name = "Agent Relay session"
  description  = "Anthropic session this workspace serves. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The relay uses it to recognize its own workspaces, dedupe redeliveries, and reconcile state after a restart."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1000
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_delivery_id" {
  name         = "agent_relay_delivery_id"
  display_name = "Agent Relay delivery"
  description  = "Work order that dispatched this build, identified by its JWT id. Agent Relay sets this when it dispatches the workspace; a human never fills it in. Tracing only: it rotates on every delivery attempt of the same session, so it identifies the delivery rather than the session."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1001
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_pool" {
  name         = "agent_relay_pool"
  display_name = "Agent Relay pool"
  description  = "Agent Relay runner pool that dispatched this build. Agent Relay sets this when it dispatches the workspace; a human never fills it in. One relay can serve several pools, each with its own Anthropic credential, organization, and template."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1002
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_credential" {
  name         = "agent_relay_credential"
  display_name = "Agent Relay credential"
  description  = "Single-use work order JWT the runner authenticates to Anthropic with. Agent Relay sets this when it dispatches the workspace; a human never fills it in. Ephemeral: it is valid for one session and is not reused on a later build."
  type         = "string"
  ephemeral    = true
  mutable      = true
  default      = ""
  order        = 1003
  styling = jsonencode({
    disabled    = true
    mask_input  = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_claude_code_lock_to_account" {
  name         = "agent_relay_claude_code_lock_to_account"
  display_name = "Claude Code account lock"
  description  = "Anthropic account the runner is locked to, so a session can only ever be served for the account it was issued for. Agent Relay sets this from the work order's account_id claim; a human never fills it in."
  type         = "string"
  ephemeral    = true
  mutable      = true
  default      = ""
  order        = 1004
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_attempt" {
  name         = "agent_relay_attempt"
  display_name = "Agent Relay delivery attempt"
  description  = "Delivery attempt this build was dispatched on, counted by Anthropic. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The relay echoes it back when it reports a session undeliverable, because Anthropic ignores a report that names an older attempt. Ephemeral, so a build the relay did not dispatch carries no attempt rather than a stale one."
  type         = "string"
  ephemeral    = true
  mutable      = true
  default      = ""
  order        = 1005
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

# Environment variable names are the claude CLI's contract, not
# Agent Relay's; do not rename them here.
resource "coder_env" "runner_pool_secret" {
  agent_id = var.agent_id
  name     = "SELF_HOSTED_RUNNER_POOL_SECRET"
  value    = data.coder_parameter.agent_relay_credential.value
}

resource "coder_env" "agent_relay_claude_code_lock_to_account" {
  agent_id = var.agent_id
  name     = "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT"
  value    = data.coder_parameter.agent_relay_claude_code_lock_to_account.value
}

resource "coder_script" "runner" {
  agent_id     = var.agent_id
  display_name = "Claude Code runner"
  icon         = "/emojis/1f916.png"
  run_on_start = true
  script = templatefile("${path.module}/run.sh.tftpl", {
    cli_binary  = var.cli_binary
    install_cli = var.install_cli
    state_file  = var.state_file
    log_file    = var.log_file
  })
}

# The coder provider has no standalone agent-metadata resource: the
# metadata block belongs to coder_agent, which the template owns. The
# template must add the block below; this output renders its script so
# the state file path stays in one place. See README.
output "status_metadata_script" {
  description = "Script body for the agent_relay_status agent metadata item the template must declare on its coder_agent."
  value = templatefile("${path.module}/status.sh.tftpl", {
    state_file          = var.state_file
    log_file            = var.log_file
    serving_log_pattern = var.serving_log_pattern
  })
}

output "dispatched" {
  description = "Whether this workspace was spawned by Agent Relay (credential set) or manually (empty)."
  value       = data.coder_parameter.agent_relay_credential.value != ""
}
