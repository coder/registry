# Cursor self-hosted worker module for Coder templates.
#
# A Cursor-compatible template includes this module and passes it the
# workspace's coder_agent id. It declares every rich parameter
# Agent Relay stamps on a build and runs `agent worker ... start`
# via a coder_script.
#
# Parameter contract (enforced by Agent Relay at startup via the dynamic
# parameters evaluate endpoint):
#
#   - agent_relay_session_id, agent_relay_delivery_id, agent_relay_pool,
#     agent_relay_cursor_pool_name, agent_relay_cursor_idle_release_timeout,
#     and agent_relay_cursor_repo_url are persistent state: coderd only
#     stores parameter values the template declares, and Agent Relay's
#     dedupe and reconciliation query workspaces with `param:` search
#     filters on them. agent_relay_cursor_repo_url is stamped on every
#     build (empty for repo-less pools) so the contract stays static.
#   - agent_relay_credential is an ephemeral worker input, reset between
#     builds.
#
# The worker's lifecycle is published through the agent_relay_status agent
# metadata item, whose script this module renders. The script starts
# the worker detached and exits so the agent reaches the ready
# lifecycle state rather than sitting in starting for the whole
# session.

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
  description = "ID of the coder_agent that should receive the worker env vars and run the worker script."
}

variable "cli_binary" {
  type        = string
  default     = "agent"
  description = "Path to the Cursor CLI binary in the workspace image. Override to test a beta build."
}

variable "install_cli" {
  type        = bool
  default     = true
  description = "Install the Cursor CLI (curl https://cursor.com/install -fsSL | bash) when the workspace starts and the CLI is not already on PATH. Defaults to true so a template works against an image that has no CLI. A CLI already in the image is used as is and never upgraded, which is the recommended and fastest path: the download only runs when the binary is missing, and it then needs outbound access to cursor.com and spends part of the claim-to-ready window."
}

variable "computer_use" {
  type        = bool
  default     = false
  description = "Start the worker with --computer-use. Requires the computer-use packages in the workspace image."
}

variable "state_file" {
  type        = string
  default     = "/tmp/agent-relay/worker-state"
  description = "Path the worker supervisor writes its lifecycle state to, read by the agent_relay_status agent metadata item."
}

variable "log_file" {
  type        = string
  default     = "/tmp/agent-relay/worker.log"
  description = "Path the detached worker's output is written to."
}

variable "serving_log_pattern" {
  type        = string
  default     = "in use"
  description = "Worker log substring that means a chat session attached. At default verbosity the Cursor CLI log carries no session line, so this only works with verbose worker logs and typically never matches; Agent Relay's status page overlays Cursor's authoritative in-use worker state regardless, so the working versus serving distinction here is best-effort and purely cosmetic. A pattern that never matches degrades to working and affects nothing else."
}

data "coder_parameter" "agent_relay_session_id" {
  name         = "agent_relay_session_id"
  display_name = "Agent Relay session"
  description  = "Cursor cloud agent request this workspace serves. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The relay uses it to recognize its own workspaces, dedupe redeliveries, and reconcile state after a restart."
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
  description  = "Worker identity Agent Relay claimed the request with. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The worker CLI presents it back to Cursor through CURSOR_AGENT_WORKER_ID, which is how Cursor matches the worker to the request."
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
  description  = "Agent Relay worker pool that dispatched this build. Agent Relay sets this when it dispatches the workspace; a human never fills it in. One relay can serve several pools, each with its own Cursor credential, organization, and template."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1002
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_cursor_pool_name" {
  name         = "agent_relay_cursor_pool_name"
  display_name = "Cursor pool"
  description  = "Pool name on Cursor's side that the worker registers under, which is what a developer selects when starting a session. Agent Relay sets this from the pool configuration; a human never fills it in. It is distinct from the relay's own label for the pool."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1003
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_cursor_idle_release_timeout" {
  name         = "agent_relay_cursor_idle_release_timeout"
  display_name = "Cursor idle release timeout"
  description  = "Seconds the worker stays connected after a session ends, waiting for a follow-up, before releasing itself and exiting. Agent Relay sets this from the pool configuration; a human never fills it in. The clean exit is what tells the relay to delete the workspace."
  type         = "string"
  mutable      = true
  default      = "600"
  order        = 1004
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_cursor_repo_url" {
  name         = "agent_relay_cursor_repo_url"
  display_name = "Cursor repository"
  description  = "Repository the request targets, empty for pools that are not repo-scoped. Agent Relay sets this from the pool configuration; a human never fills it in. Cloning it and providing SCM credentials is the template's job; refer to the module README."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1005
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_credential" {
  name         = "agent_relay_credential"
  display_name = "Agent Relay credential"
  description  = "Cursor service account API key the worker authenticates with. Agent Relay sets this when it dispatches the workspace; a human never fills it in. Ephemeral: it is supplied per build and is not reused on a later one."
  type         = "string"
  ephemeral    = true
  mutable      = true
  default      = ""
  order        = 1006
  styling = jsonencode({
    disabled    = true
    mask_input  = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

# Environment variable names are the Cursor CLI's contract, not
# Agent Relay's; do not rename them here.
resource "coder_env" "cursor_api_key" {
  agent_id = var.agent_id
  name     = "CURSOR_API_KEY"
  value    = data.coder_parameter.agent_relay_credential.value
}

resource "coder_env" "cursor_agent_worker_id" {
  agent_id = var.agent_id
  name     = "CURSOR_AGENT_WORKER_ID"
  value    = data.coder_parameter.agent_relay_delivery_id.value
}

resource "coder_script" "worker" {
  agent_id     = var.agent_id
  display_name = "Cursor worker"
  icon         = "/icon/cursor.svg"
  run_on_start = true
  script = templatefile("${path.module}/run.sh.tftpl", {
    cli_binary           = var.cli_binary
    install_cli          = var.install_cli
    computer_use         = var.computer_use
    state_file           = var.state_file
    log_file             = var.log_file
    pool_name            = data.coder_parameter.agent_relay_cursor_pool_name.value
    idle_release_timeout = data.coder_parameter.agent_relay_cursor_idle_release_timeout.value
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
