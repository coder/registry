# Devin Outposts remote module for Coder templates.
#
# A Devin-compatible template includes this module and passes it the
# workspace's coder_agent id. It declares every rich parameter Agent Relay
# stamps on a build and runs `devin-remote serve` via a coder_script.
#
# Scripts run through coder-utils, which orders the install step before
# the start step and keeps a copy of each script and its output under
# module_directory for debugging. The pre-install and stop steps render
# the same best-effort process cleanup script.
#
# Parameter contract (enforced by Agent Relay at startup via the dynamic
# parameters evaluate endpoint):
#
#   - agent_relay_session_id, agent_relay_delivery_id, agent_relay_pool,
#     and the agent_relay_devin_* parameters are persistent state: coderd
#     only stores parameter values the template declares, and Agent Relay's
#     dedupe and reconciliation query workspaces with `param:` search
#     filters on them. Every one is stamped on every relay build (empty
#     when Devin reports nothing) so the contract stays static.
#   - agent_relay_client_platform and agent_relay_devin_session_url are
#     optional attribution; relays that predate them never set them.
#
# The connect token is not a parameter. Agent Relay sends it as an
# ephemeral workspace secret, which the agent injects as
# AGENT_RELAY_DEVIN_TOKEN. It never reaches the provisioner, Terraform
# state, or the build's parameters, so nothing in this module can read it.
#
# The remote's lifecycle is published through the agent_relay_status agent
# metadata item, whose script this module renders. The start script
# launches the remote detached and exits so the agent reaches the ready
# lifecycle state rather than sitting in starting for the whole session.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "ID of the coder_agent that should receive the remote's env vars and run the remote's scripts."
  type        = string
}

variable "install_remote" {
  description = "Download devin-remote from static_base_url when the workspace starts a relay session, verify it against its published SHA-256, and cache it under $HOME/.devin/worker/cache. The build pins the version through agent_relay_devin_remote_binary_sha, or the latest release when that is empty. Set to false and set remote_binary for an image that bakes the binary."
  type        = bool
  default     = true
}

variable "remote_binary" {
  description = "Path or command name of a devin-remote binary baked into the image. When set, the module runs it and downloads nothing. Empty uses the binary install_remote downloads."
  type        = string
  default     = ""

  # Passed to the supervisor as an argument and rendered into the status
  # scripts as a command word, so it is restricted to a command name or
  # path: no whitespace, quotes, or other shell metacharacters.
  validation {
    condition     = var.remote_binary == "" || can(regex("^[A-Za-z0-9._/@+-]+$", var.remote_binary))
    error_message = "remote_binary must be empty or a command name or path made of letters, digits, and . _ / @ + - only."
  }

  validation {
    condition     = var.install_remote || var.remote_binary != ""
    error_message = "remote_binary must be set when install_remote is false."
  }
}

variable "static_base_url" {
  description = "Base URL that serves latest_linux_<arch>, devin-remote_<sha>_linux_<arch>, and its .sha256. Override only to use a mirror."
  type        = string
  default     = "https://static.devin.ai/devin-rs/remote"

  # The binary runs with the session's connect token, so it must come over
  # TLS. Plain HTTP is allowed only on loopback, which is what tests use.
  validation {
    condition     = startswith(var.static_base_url, "https://") || can(regex("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?(/|$)", var.static_base_url))
    error_message = "static_base_url must start with https://, or with http://localhost or http://127.0.0.1."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9._~:/%+@-]+$", var.static_base_url))
    error_message = "static_base_url must not contain whitespace, quotes, or other shell metacharacters."
  }
}

variable "workdir" {
  description = "Working directory devin-remote is started in. Devin clones repositories under <workdir>/repos and writes its .devin-outpost-stamps there. Keep it on a volume that survives a workspace stop so a suspended session resumes with its files."
  type        = string
  default     = "$HOME/devin"

  # Expanded into the start script and the supervisor, so it is restricted
  # to an absolute path or one under $HOME made of safe characters.
  validation {
    condition     = can(regex("^(\\$HOME(/[A-Za-z0-9._/@+-]*)?|/[A-Za-z0-9._/@+-]*)$", var.workdir))
    error_message = "workdir must be an absolute path, $HOME, or a path under $HOME/, made of letters, digits, and . _ / @ + - only."
  }
}

variable "state_dir" {
  description = "Directory that holds one devin-remote state directory per session. The remote gets DEVIN_REMOTE_STATE_DIR=<state_dir>/<session id>. Keep it on a volume that survives a workspace stop."
  type        = string
  default     = "$HOME/.devin/worker/sessions"

  validation {
    condition     = can(regex("^(\\$HOME(/[A-Za-z0-9._/@+-]*)?|/[A-Za-z0-9._/@+-]*)$", var.state_dir))
    error_message = "state_dir must be an absolute path, $HOME, or a path under $HOME/, made of letters, digits, and . _ / @ + - only."
  }
}

variable "chrome_path" {
  description = "Path to a Chrome or Chromium binary for Devin's browser, passed as DEVIN_CHROME_PATH. Empty lets devin-remote find one itself."
  type        = string
  default     = ""

  validation {
    condition     = var.chrome_path == "" || can(regex("^(\\$HOME/[A-Za-z0-9._/@+-]*|/[A-Za-z0-9._/@+-]*)$", var.chrome_path))
    error_message = "chrome_path must be empty, an absolute path, or a path under $HOME/, made of letters, digits, and . _ / @ + - only."
  }
}

variable "desktop" {
  description = "Start devin-remote with DEVIN_OUTPOST_DESKTOP=true so Devin uses the workspace's desktop. Requires a display (DISPLAY or WAYLAND_DISPLAY) in the agent's environment."
  type        = bool
  default     = false
}

variable "state_file" {
  description = "Path the remote supervisor writes its lifecycle state to, read by the agent_relay_status agent metadata item."
  type        = string
  default     = "$HOME/.coder-modules/coder/agent-relay-devin/remote-state"

  # Expanded into the supervisor's code, like workdir.
  validation {
    condition     = can(regex("^(\\$HOME/[A-Za-z0-9._/@+-]*|/[A-Za-z0-9._/@+-]*)$", var.state_file))
    error_message = "state_file must be an absolute path or a path under $HOME/, made of letters, digits, and . _ / @ + - only."
  }
}

variable "log_file" {
  description = "Path the detached remote's output is written to."
  type        = string
  default     = "$HOME/.coder-modules/coder/agent-relay-devin/logs/remote.log"

  validation {
    condition     = can(regex("^(\\$HOME/[A-Za-z0-9._/@+-]*|/[A-Za-z0-9._/@+-]*)$", var.log_file))
    error_message = "log_file must be an absolute path or a path under $HOME/, made of letters, digits, and . _ / @ + - only."
  }
}

variable "serving_log_pattern" {
  description = "Remote log substring that means devin-remote connected to Devin's outpost gateway. Matched as a fixed string after ANSI escape sequences are stripped. Until it matches, agent_relay_status reports working; after, serving. It also ends the connect_timeout watchdog."
  type        = string
  default     = "connected to outpost gateway endpoint="

  # grep -F with an empty pattern matches every line, which would report
  # serving on any output and disable the connect watchdog.
  validation {
    condition     = length(var.serving_log_pattern) > 0
    error_message = "serving_log_pattern must not be empty; an empty pattern matches every log line."
  }
}

variable "connect_timeout" {
  description = "Seconds devin-remote has to log serving_log_pattern after it starts. Past it, the supervisor stops the remote and reports failed connect-timeout. A rejected token makes devin-remote retry forever, so this is what turns it into a failure."
  type        = number
  default     = 300

  validation {
    condition     = var.connect_timeout > 0 && floor(var.connect_timeout) == var.connect_timeout
    error_message = "connect_timeout must be a positive whole number of seconds."
  }
}

data "coder_parameter" "agent_relay_session_id" {
  name         = "agent_relay_session_id"
  display_name = "Agent Relay session"
  description  = "Devin session this workspace serves. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The relay uses it to recognize its own workspaces, dedupe redeliveries, and reconcile state after a restart, and the remote gets it as DEVIN_OUTPOST_SESSION_ID."
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
  description  = "Identity of the dispatch that built this workspace. Agent Relay sets this when it dispatches the workspace; a human never fills it in."
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
  description  = "Agent Relay pool that dispatched this build. Agent Relay sets this when it dispatches the workspace; a human never fills it in. One relay can serve several pools, each with its own Devin outpost, organization, and template."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1002
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_outpost_id" {
  name         = "agent_relay_devin_outpost_id"
  display_name = "Devin outpost"
  description  = "Devin outpost whose queue the session came from. Agent Relay sets this from the pool configuration; a human never fills it in."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1003
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_gateway_url" {
  name         = "agent_relay_devin_gateway_url"
  display_name = "Devin gateway"
  description  = "Outpost gateway URL Devin returned with the claim. Agent Relay sets this when it dispatches the workspace; a human never fills it in. The remote gets it as DEVIN_OUTPOST_GATEWAY_URL."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1004
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_remote_binary_sha" {
  name         = "agent_relay_devin_remote_binary_sha"
  display_name = "Devin remote version"
  description  = "devin-remote build Devin asked for, as a short commit SHA. Agent Relay sets this from the queue entry; a human never fills it in. Empty uses the latest release."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1005
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_session_kind" {
  name         = "agent_relay_devin_session_kind"
  display_name = "Devin session kind"
  description  = "new for a first start, resume when Agent Relay restarts this workspace for a suspended session. Agent Relay sets this when it dispatches the workspace; a human never fills it in."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1006
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_image" {
  name         = "agent_relay_devin_image"
  display_name = "Devin image"
  description  = "Image the Devin session asked for, or empty. Agent Relay sets this from the queue entry; a human never fills it in. The module does not act on it."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1007
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_network_policy" {
  name         = "agent_relay_devin_network_policy"
  display_name = "Devin network policy"
  description  = "Network policy the Devin session asked for, as JSON, or empty. Agent Relay sets this from the queue entry; a human never fills it in. The module does not enforce it."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1008
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_client_platform" {
  name         = "agent_relay_client_platform"
  display_name = "Devin client platform"
  description  = "Surface the session was created from, as Devin reports it. Agent Relay sets this when it dispatches the workspace; a human never fills it in. Exposed to the workspace as AGENT_RELAY_CLIENT_PLATFORM so a template can vary its setup by origin."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1009
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

data "coder_parameter" "agent_relay_devin_session_url" {
  name         = "agent_relay_devin_session_url"
  display_name = "Devin session URL"
  description  = "Link to the session in Devin's web app. Agent Relay sets this when it dispatches the workspace; a human never fills it in. An https URL adds an Open in Devin button."
  type         = "string"
  mutable      = true
  default      = ""
  order        = 1010
  styling = jsonencode({
    disabled    = true
    placeholder = "Set by Agent Relay on dispatch"
  })
}

# Parameter values reach the scripts through the environment, never through
# the script text, so a value with shell metacharacters is data and not
# code. There is deliberately no AGENT_RELAY_DEVIN_TOKEN here: Agent Relay
# delivers the connect token as a workspace secret of that name, which the
# agent injects, and a coder_env of the same name would put it in state.
resource "coder_env" "agent_relay_session_id" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_SESSION_ID"
  value    = data.coder_parameter.agent_relay_session_id.value
}

resource "coder_env" "agent_relay_devin_outpost_id" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_OUTPOST_ID"
  value    = data.coder_parameter.agent_relay_devin_outpost_id.value
}

resource "coder_env" "agent_relay_devin_gateway_url" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_GATEWAY_URL"
  value    = data.coder_parameter.agent_relay_devin_gateway_url.value
}

resource "coder_env" "agent_relay_devin_remote_binary_sha" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA"
  value    = data.coder_parameter.agent_relay_devin_remote_binary_sha.value
}

resource "coder_env" "agent_relay_devin_session_kind" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_SESSION_KIND"
  value    = data.coder_parameter.agent_relay_devin_session_kind.value
}

# The module does not act on the image or the network policy. They are
# exported so a template's own scripts can.
resource "coder_env" "agent_relay_devin_image" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_IMAGE"
  value    = data.coder_parameter.agent_relay_devin_image.value
}

resource "coder_env" "agent_relay_devin_network_policy" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_DEVIN_NETWORK_POLICY"
  value    = data.coder_parameter.agent_relay_devin_network_policy.value
}

resource "coder_env" "agent_relay_client_platform" {
  agent_id = var.agent_id
  name     = "AGENT_RELAY_CLIENT_PLATFORM"
  value    = data.coder_parameter.agent_relay_client_platform.value
}

locals {
  # coder-utils requires this exact layout. Scripts land in scripts/ and
  # their output in logs/; the remote state and log default to the same
  # tree so one directory holds everything a debugger needs.
  module_directory = "$HOME/.coder-modules/coder/agent-relay-devin"

  # The status scripts recognize the remote by this name in its command
  # line. A downloaded binary is cached as devin-remote_<sha>_linux_<arch>.
  remote_name = var.remote_binary != "" ? basename(var.remote_binary) : "devin-remote"

  session_url = data.coder_parameter.agent_relay_devin_session_url.value

  cleanup_script = templatefile("${path.module}/cleanup.sh.tftpl", {
    module_directory = local.module_directory
    state_file       = var.state_file
    stop_mode        = false
  })

  stop_script = templatefile("${path.module}/cleanup.sh.tftpl", {
    module_directory = local.module_directory
    state_file       = var.state_file
    stop_mode        = true
  })

  install_script = templatefile("${path.module}/install.sh.tftpl", {
    module_directory = local.module_directory
    remote_binary    = var.remote_binary
    static_base_url  = trimsuffix(var.static_base_url, "/")
    download_proto   = startswith(var.static_base_url, "https://") ? "=https" : "=http"
  })

  start_script = templatefile("${path.module}/start.sh.tftpl", {
    module_directory    = local.module_directory
    remote_binary       = var.remote_binary
    workdir             = var.workdir
    state_dir           = var.state_dir
    chrome_path         = var.chrome_path
    desktop             = var.desktop
    state_file          = var.state_file
    log_file            = var.log_file
    serving_log_pattern = base64encode(var.serving_log_pattern)
    connect_timeout     = var.connect_timeout
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "Devin remote"
  icon                = "/icon/devin.svg"
  pre_install_script  = local.cleanup_script
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_script" "stop_remote" {
  agent_id     = var.agent_id
  display_name = "Devin remote: Stop Script"
  icon         = "/icon/devin.svg"
  run_on_stop  = true
  timeout      = 20
  script       = local.stop_script
}

# Devin's web app is the only client that opens a session. A hand-created
# workspace, or a relay that does not report the URL, gets no button.
resource "coder_app" "devin_session" {
  count        = startswith(local.session_url, "https://") ? 1 : 0
  agent_id     = var.agent_id
  slug         = "devin-session"
  display_name = "Open in Devin"
  icon         = "/icon/devin.svg"
  url          = local.session_url
  external     = true
}

# The coder provider has no standalone agent-metadata resource: the
# metadata block belongs to coder_agent, which the template owns. The
# template must add the block below; this output renders its script so
# the state file path stays in one place. See README.
output "status_metadata_script" {
  description = "Script body for the agent_relay_status agent metadata item the template must declare on its coder_agent."
  value = templatefile("${path.module}/status.sh.tftpl", {
    remote_name         = local.remote_name
    state_file          = var.state_file
    log_file            = var.log_file
    serving_log_pattern = base64encode(var.serving_log_pattern)
  })
}

output "session_attached_metadata_script" {
  description = "Script body for the agent_relay_session_attached agent metadata item. Prints attached while the remote runs and stopped otherwise; see README."
  value = templatefile("${path.module}/session_attached.sh.tftpl", {
    remote_name = local.remote_name
    state_file  = var.state_file
  })
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order. A template can `coder exp sync want <self> <these>` to run its own scripts after the remote is up."
  value       = module.coder_utils.scripts
}

output "dispatched" {
  description = "Whether Agent Relay created this workspace. Stays true on every later build of it, including one a person restarts; whether the current build has a connect token is decided by the start script, not here."
  value       = data.coder_parameter.agent_relay_delivery_id.value != ""
}

output "session_id" {
  description = "Devin session id stamped in agent_relay_session_id. Empty when a person created the workspace."
  value       = data.coder_parameter.agent_relay_session_id.value
}
