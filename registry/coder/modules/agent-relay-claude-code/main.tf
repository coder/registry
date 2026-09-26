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
#
# Scripts run through coder-utils, which orders the install step before
# the start step and keeps a copy of each script and its output under
# module_directory for debugging.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
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

  # Rendered into the start script and the supervisor as a command word,
  # so it is restricted to a command name or path: no whitespace, quotes,
  # or other shell metacharacters.
  validation {
    condition     = can(regex("^[A-Za-z0-9._/@+-]+$", var.cli_binary))
    error_message = "cli_binary must be a command name or path made of letters, digits, and . _ / @ + - only."
  }
}

variable "install_cli" {
  type        = bool
  default     = true
  description = "Install the Claude Code CLI (curl https://claude.ai/install.sh -fsSL | bash) when the workspace starts and the CLI is not already on PATH. Defaults to true so a template works against an image that has no CLI. A CLI already in the image is used as is and never upgraded, which is the recommended and fastest path: the download only runs when the binary is missing, and it spends part of the claim-to-ready window when it does."
}

variable "state_file" {
  type        = string
  default     = "$HOME/.coder-modules/coder/agent-relay-claude-code/runner-state"
  description = "Path the runner supervisor writes its lifecycle state to, read by the agent_relay_status agent metadata item."
}

variable "log_file" {
  type        = string
  default     = "$HOME/.coder-modules/coder/agent-relay-claude-code/logs/runner.log"
  description = "Path the detached runner's output is written to."
}

variable "base_dir" {
  type        = string
  default     = "$HOME/workspace"
  description = "Directory the runner checks sessions out under (the CLI's --base-dir). Created at start. The CLI's own default is /workspace, which a plain image does not have and the agent user cannot create."
}

variable "exit_if_unused_min" {
  type        = number
  default     = 10
  description = "Minutes the runner waits for a session before exiting on its own (the CLI's --exit-if-unused-min). A dispatched workspace that never receives its session would otherwise report working forever and never be reaped. 0 disables the bound. Keep it above Agent Relay's spawn budget, which for Claude Code pools is the work order's issue time plus 300s (dispatch_deadline is the Cursor pools' setting and does not apply here)."

  validation {
    condition     = var.exit_if_unused_min >= 0 && floor(var.exit_if_unused_min) == var.exit_if_unused_min
    error_message = "exit_if_unused_min must be a whole number of minutes, 0 to disable."
  }
}

variable "drain_wait_sec" {
  description = "Seconds the runner waits for the session's in-flight turn and background tasks to finish before stopping the session process, once it is asked to shut down (the CLI's --drain-wait-sec). 0 leaves the flag off, so a template can set SELF_HOSTED_RUNNER_DRAIN_WAIT_MS itself; note that one is milliseconds. Every second here is added to shutdown_grace_seconds, which the template must honor."
  type        = number
  default     = 0

  validation {
    condition     = var.drain_wait_sec >= 0 && floor(var.drain_wait_sec) == var.drain_wait_sec
    error_message = "drain_wait_sec must be a whole number of seconds, 0 to disable."
  }
}

variable "push_outcome_on_release" {
  description = "Push the session's outcome branch to origin before deleting it when the runner ends a session it could not complete (the CLI's --push-outcome-on-release), so commits survive an ephemeral workspace being torn down and a resumed session continues from them. Fires on every runner-initiated incomplete end, which includes idle-release and failed sessions, so it needs git auth in the workspace and it creates branches for those too. Adds 30s to shutdown_grace_seconds. false leaves the flag off, so a template can set SELF_HOSTED_RUNNER_PUSH_OUTCOME_ON_RELEASE itself."
  type        = bool
  default     = false
}

variable "client_label" {
  description = "Label the runner registers with, shown beside it in the Anthropic console (the CLI's --client-label). Empty uses <owner>/<workspace>, so a runner is identifiable without the template having to set a hostname. The label is display only: it is never used for authorization or routing, and it cannot steer which sessions this runner is assigned."
  type        = string
  default     = ""
}

variable "serving_log_pattern" {
  type        = string
  default     = "Picked up session"
  description = "Runner log substring that means a session was claimed. Only distinguishes the agent_relay_status values working and serving; a stale pattern degrades to working and affects nothing else."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

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
resource "coder_env" "runner_environment_secret" {
  agent_id = var.agent_id
  name     = "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET"
  value    = data.coder_parameter.agent_relay_credential.value
}

resource "coder_env" "agent_relay_claude_code_lock_to_account" {
  agent_id = var.agent_id
  name     = "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT"
  value    = data.coder_parameter.agent_relay_claude_code_lock_to_account.value
}

locals {
  # coder-utils requires this exact layout. Scripts land in scripts/ and
  # their output in logs/; the runner state and log default to the same
  # tree so one directory holds everything a debugger needs.
  module_directory = "$HOME/.coder-modules/coder/agent-relay-claude-code"

  # coder-utils prefixes its own steps with this; the stop step is a
  # plain coder_script, so it joins the same naming by hand.
  display_name_prefix = "Claude Code runner"
  icon                = "/emojis/1f916.png"

  client_label = var.client_label != "" ? var.client_label : "${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"

  install_script = templatefile("${path.module}/install.sh.tftpl", {
    cli_binary  = var.cli_binary
    install_cli = var.install_cli
  })

  start_script = templatefile("${path.module}/start.sh.tftpl", {
    cli_binary              = var.cli_binary
    state_file              = var.state_file
    log_file                = var.log_file
    base_dir                = var.base_dir
    exit_if_unused_min      = var.exit_if_unused_min
    drain_wait_sec          = var.drain_wait_sec
    push_outcome_on_release = var.push_outcome_on_release
    # Free-form text: base64 so a label with quotes or spaces can never
    # become shell in the supervisor script.
    client_label = base64encode(local.client_label)
  })

  # What the runner itself needs once it is signalled: 80s to stop the
  # Claude process and run the post-session hook, plus up to 20s for a
  # session release already in flight. The two optional behaviors extend
  # it by exactly what their flags document. This is what the stop script
  # waits for, because it starts counting when it runs.
  runner_budget = 100 + var.drain_wait_sec + (var.push_outcome_on_release ? 30 : 0)

  # What the platform must grant, counted from the signal: the runner's
  # budget plus the 5s the agent spends shutting down SSH before it runs
  # stop scripts at all. Larger than runner_budget by exactly that gap,
  # so the script's own wait always ends first.
  shutdown_grace_seconds = local.runner_budget + 5

  stop_script = templatefile("${path.module}/stop.sh.tftpl", {
    cli_binary      = var.cli_binary
    state_file      = var.state_file
    drain_timeout_s = local.runner_budget
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = local.display_name_prefix
  icon                = local.icon
  install_script      = local.install_script
  start_script        = local.start_script
}

# coder-utils runs install and start steps only, so the stop step is a
# plain coder_script beside it. It is deliberately outside the
# `coder exp sync` ordering the module's other scripts take part in:
# nothing runs after it.
resource "coder_script" "stop" {
  agent_id           = var.agent_id
  display_name       = "${local.display_name_prefix}: Stop Script"
  icon               = local.icon
  run_on_start       = false
  run_on_stop        = true
  start_blocks_login = false
  script             = local.stop_script
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
    serving_log_pattern = base64encode(var.serving_log_pattern)
  })
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order. A template can `coder exp sync want <self> <these>` to run its own scripts after the runner is up."
  value       = module.coder_utils.scripts
}

output "shutdown_grace_seconds" {
  description = "Seconds the platform must give the workspace to shut down for the runner to drain instead of being killed. Wire it into the compute resource the template owns: docker_container.destroy_grace_seconds, or a pod spec's termination_grace_period_seconds. A module owns no compute resource and cannot set this itself. The value is a ceiling, not a fixed wait: a workspace whose runner has already finished stops immediately."
  value       = local.shutdown_grace_seconds
}

output "dispatched" {
  description = "Whether this workspace was spawned by Agent Relay (credential set) or manually (empty)."
  value       = data.coder_parameter.agent_relay_credential.value != ""
}
