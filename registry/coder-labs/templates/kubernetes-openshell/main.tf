terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
  }
}

provider "coder" {}

variable "use_kubeconfig" {
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces. A valid "~/.kube/config" must be present on the Coder host.
  EOF
  type        = bool
  default     = false
}

variable "namespace" {
  description = "The namespace for workspaces, which is the gateway's sandbox namespace. cluster/ creates it with the Role and the gateway credentials."
  type        = string

  validation {
    condition     = length(trimspace(var.namespace)) > 0
    error_message = "namespace must not be empty."
  }
}

variable "workspace_image" {
  description = "The workspace image. Build it from build/Dockerfile, with a Coder agent that matches your Coder server. Use a fixed tag or a digest, not :latest."
  type        = string

  validation {
    condition = (
      length(trimspace(var.workspace_image)) > 0 &&
      !endswith(var.workspace_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.workspace_image), length(split("/", var.workspace_image)) - 1)))
    )
    error_message = "workspace_image must have a tag other than :latest, or a digest, such as registry.example.com/coder/workspace:v2.30.0."
  }
}

variable "launcher_image" {
  description = "The launcher image with the openshell CLI. Build it from build/launcher/Dockerfile, with the CLI version of your gateway. Use a fixed tag or a digest, not :latest."
  type        = string

  validation {
    condition = (
      length(trimspace(var.launcher_image)) > 0 &&
      !endswith(var.launcher_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.launcher_image), length(split("/", var.launcher_image)) - 1)))
    )
    error_message = "launcher_image must have a tag other than :latest, or a digest, such as registry.example.com/coder/openshell-launcher:0.1.5."
  }
}

variable "openshell_gateway_url" {
  description = "The URL of the OpenShell gateway, as the launcher Pods in the namespace see it."
  type        = string
  default     = "https://openshell.openshell.svc.cluster.local:8080"
}

variable "openshell_workspace" {
  description = "The OpenShell workspace that owns the sandboxes."
  type        = string
  default     = "default"
}

# A comma-separated string, not a list, because Coder checks presets with
# every template variable as a string.
variable "runtimes" {
  description = "Kata runtimes that users can pick in addition to the node's container runtime, comma-separated: kata-qemu, kata-clh. Each RuntimeClass needs the label openshell.ai/sandbox-attachable=true, which cluster/ adds. gVisor does not work, because it has no Landlock. Empty offers none."
  type        = string
  default     = ""

  validation {
    condition = (
      length(compact(split(",", replace(var.runtimes, " ", "")))) == length(distinct(compact(split(",", replace(var.runtimes, " ", ""))))) &&
      alltrue([for r in compact(split(",", replace(var.runtimes, " ", ""))) : contains(["kata-qemu", "kata-clh"], r)])
    )
    error_message = "runtimes can list only kata-qemu and kata-clh, comma-separated, each once."
  }
}

variable "cpu" {
  description = "The CPU of each sandbox, as a Kubernetes quantity such as 1 or 500m. OpenShell sets it as both the request and the limit."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.cpu))
    error_message = "cpu must be a Kubernetes CPU quantity, such as 1, 1.5, or 500m."
  }
}

variable "memory" {
  description = "The memory of each sandbox, as a Kubernetes quantity such as 2Gi. OpenShell sets it as both the request and the limit."
  type        = string
  default     = "2Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory))
    error_message = "memory must be a Kubernetes quantity in Mi or Gi, such as 2Gi."
  }
}

variable "home_disk_size" {
  description = "The size of the persistent home disk in GiB."
  type        = number
  default     = 10

  validation {
    condition     = var.home_disk_size >= 1
    error_message = "home_disk_size must be at least 1."
  }
}

variable "storage_class_name" {
  description = "The StorageClass for the persistent home disk. Leave empty to use the cluster default. Use a class with volumeBindingMode WaitForFirstConsumer."
  type        = string
  default     = ""
}

variable "prebuild_instances" {
  description = "The number of prebuilt workspaces to keep for each preset. Prebuilds need a Coder Premium license. Set 0 to turn them off."
  type        = number
  default     = 1

  validation {
    condition     = var.prebuild_instances >= 0 && floor(var.prebuild_instances) == var.prebuild_instances
    error_message = "prebuild_instances must be a whole number, 0 or more."
  }
}

variable "git_repo_url" {
  description = "A Git repository to clone into the home over HTTPS, for example https://github.com/coder/coder. Only profiles that allow GitHub clone it. Empty clones nothing."
  type        = string
  default     = ""
}

variable "enable_ai_gateway" {
  description = "Send Claude Code requests through the Coder AI Gateway (Premium). Claude Code then reaches Anthropic through the Coder server, so it works in Fully isolated."
  type        = bool
  default     = true
}

variable "enable_claude_code" {
  description = "Add the Claude Code app and its settings. Turn this off if you build the image with INSTALL_CLAUDE_CODE=false."
  type        = bool
  default     = true
}

provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Network profiles: what a workspace can reach in addition to the Coder
# server. The OpenShell proxy matches host names. Do not add hosts that
# store user content, because the workspace can send data to them.
locals {
  github_hosts = [
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "objects.githubusercontent.com",
    "raw.githubusercontent.com",
    "release-assets.githubusercontent.com",
  ]

  profiles = {
    isolated = {
      display_name = "Fully isolated"
      description  = "Coder only. No internet."
      icon         = "/emojis/1f512.png"
      hosts        = []
    }
    github = {
      display_name = "GitHub only"
      description  = "Coder and GitHub on port 443."
      icon         = "/icon/github.svg"
      hosts        = local.github_hosts
    }
    development = {
      display_name = "GitHub and package registries"
      description  = "Coder, GitHub, npm, the Go module proxy, and PyPI on port 443."
      icon         = "/emojis/1f4e6.png"
      hosts = concat(local.github_hosts, [
        "registry.npmjs.org",
        "proxy.golang.org",
        "sum.golang.org",
        "storage.googleapis.com",
        "pypi.org",
        "files.pythonhosted.org",
      ])
    }
    custom = {
      display_name = "Custom"
      description  = "Coder and the host names and ports that you type below."
      icon         = "/emojis/270f.png"
      hosts        = []
    }
  }

  # Profiles that can reach GitHub, so they clone git_repo_url.
  github_profiles = ["github", "development"]

  runtimes = compact(split(",", replace(var.runtimes, " ", "")))
  runtime_options = {
    kata-qemu = {
      name        = "Kata microVM (QEMU)"
      description = "A small VM with its own kernel, around the OpenShell sandbox. Needs a node with /dev/kvm."
      icon        = "/icon/memory.svg"
    }
    kata-clh = {
      name        = "Kata microVM (Cloud Hypervisor)"
      description = "A small VM with a lighter hypervisor. Needs a node with /dev/kvm."
      icon        = "/icon/memory.svg"
    }
  }
}

data "coder_parameter" "network_isolation" {
  name         = "network_isolation"
  display_name = "Network isolation"
  description  = "What the workspace can reach in addition to Coder. The OpenShell proxy allows it by host name and program, and denies and logs everything else. You cannot change it after create."
  type         = "string"
  form_type    = "dropdown"
  default      = "isolated"
  mutable      = false
  order        = 1

  dynamic "option" {
    for_each = local.profiles
    content {
      name        = option.value.display_name
      description = option.value.description
      value       = option.key
      icon        = option.value.icon
    }
  }
}

# The Custom profile. These parameters appear only when you pick Custom.
locals {
  custom       = data.coder_parameter.network_isolation.value == "custom"
  custom_hosts = local.custom ? distinct([for h in jsondecode(data.coder_parameter.custom_hosts[0].value) : lower(trimspace(h)) if trimspace(h) != ""]) : []
  custom_ports = local.custom ? distinct([for p in jsondecode(data.coder_parameter.custom_ports[0].value) : tonumber(p)]) : []

  # An exact name with a dot, or "*." or "**." and at least two more labels.
  # No IP addresses. OpenShell lets an exact name reach the private address
  # it resolves to, so cluster and internal suffixes are blocked.
  host_label       = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
  host_pattern     = "^(\\*{1,2}\\.)?(${local.host_label}\\.)+[a-z][a-z0-9-]*[a-z0-9]$"
  blocked_suffixes = ["localhost", "local", "internal", "cluster.local", "svc", "localdomain"]
  custom_bad = [
    for h in local.custom_hosts : h
    if !can(regex(local.host_pattern, h)) ||
    anytrue([for b in local.blocked_suffixes : h == b || endswith(h, ".${b}")])
  ]
  custom_problems = local.custom ? length(local.custom_bad) + (length(local.custom_hosts) == 0 ? 1 : 0) + (length(local.custom_ports) == 0 ? 1 : 0) : 0
}

data "coder_parameter" "custom_hosts" {
  count        = local.custom ? 1 : 0
  name         = "custom_hosts"
  display_name = "Custom: host names"
  description  = "Type a host name such as api.example.com, *.example.com, or **.example.com and press Enter. *. matches one label and **. matches any depth, and neither matches example.com itself. Every program in the workspace can reach these hosts on the ports below."
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["github.com", "api.github.com", "registry.npmjs.org"])
  mutable      = false
  order        = 2
}

data "coder_parameter" "custom_ports" {
  count        = local.custom ? 1 : 0
  name         = "custom_ports"
  display_name = "Custom: TCP ports"
  description  = "The ports that the workspace can use on the hosts above."
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode(["443"])
  mutable      = false
  order        = 3

  option {
    name  = "443 (HTTPS)"
    value = "443"
  }
  option {
    name  = "80 (HTTP)"
    value = "80"
  }
  option {
    name  = "22 (SSH)"
    value = "22"
  }
}

# Shows the problems in the Custom fields while there are any. Its
# validation blocks Create, so the form reports them before the build.
data "coder_parameter" "custom_problems" {
  count        = local.custom_problems > 0 ? 1 : 0
  name         = "custom_problems"
  display_name = "Custom: problems to fix"
  type         = "number"
  form_type    = "input"
  default      = local.custom_problems
  mutable      = true
  order        = 4
  styling      = jsonencode({ disabled = true })

  validation {
    min   = 0
    max   = 0
    error = length(local.custom_hosts) == 0 ? "Type at least one host name." : length(local.custom_ports) == 0 ? "Pick at least one port." : "Not a host name that OpenShell can allow: ${join(", ", local.custom_bad)}."
  }
}

data "coder_parameter" "runtime" {
  count        = length(local.runtimes) > 0 ? 1 : 0
  name         = "runtime"
  display_name = "Kernel isolation"
  description  = "The RuntimeClass of the sandbox Pod. The network and file rules are the same for every option."
  type         = "string"
  form_type    = "dropdown"
  default      = "none"
  mutable      = false
  order        = 5

  option {
    name        = "None"
    value       = "none"
    description = "The node's container runtime, with Landlock and seccomp. The sandbox shares the node kernel. The fastest."
    icon        = "/icon/kubernetes.svg"
  }
  dynamic "option" {
    for_each = local.runtimes
    content {
      name        = local.runtime_options[option.value].name
      value       = option.value
      description = local.runtime_options[option.value].description
      icon        = local.runtime_options[option.value].icon
    }
  }
}

# One preset for each fixed profile, on the node's container runtime. A
# preset sets every immutable parameter, so a claimed prebuild never
# changes one.
data "coder_workspace_preset" "profile" {
  for_each    = { for k, v in local.profiles : k => v if k != "custom" }
  name        = each.value.display_name
  description = each.value.description
  icon        = each.value.icon
  default     = each.key == "isolated"
  parameters = merge(
    { network_isolation = each.key },
    length(local.runtimes) > 0 ? { runtime = "none" } : {},
  )

  dynamic "prebuilds" {
    for_each = var.prebuild_instances > 0 ? [1] : []
    content {
      instances = var.prebuild_instances
    }
  }
}

locals {
  name    = "coder-${data.coder_workspace.me.id}"
  runtime = try(data.coder_parameter.runtime[0].value, "none")
  profile = local.profiles[data.coder_parameter.network_isolation.value]
  # OpenShell sandbox names have at most 19 characters.
  sandbox_name = "coder-${substr(replace(data.coder_workspace.me.id, "-", ""), 0, 13)}"
  home         = "/sandbox/home"

  # Labels stay the same when a prebuilt workspace is claimed, so a claim
  # does not change the launcher Pod.
  labels = {
    "app.kubernetes.io/name"    = "coder-workspace"
    "app.kubernetes.io/part-of" = "coder"
    "com.coder.resource"        = "true"
    "com.coder.workspace.id"    = data.coder_workspace.me.id
  }
  owner_annotations = {
    "com.coder.workspace.name" = data.coder_workspace.me.name
    "com.coder.user.id"        = data.coder_workspace_owner.me.id
    "com.coder.user.username"  = data.coder_workspace_owner.me.name
  }

  # The agent dials the access URL, so the policy always allows it.
  access_url  = regex("^(?P<scheme>https?)://(?P<host>[^:/]+)(?::(?P<port>[0-9]+))?", data.coder_workspace.me.access_url)
  access_port = tonumber(coalesce(local.access_url.port, local.access_url.scheme == "https" ? "443" : "80"))

  # The OpenShell sandbox policy. A network rule names the programs that may
  # use it, and a program started by a listed program gets its rules, so
  # every shell and tool that the agent starts can reach Coder. OpenShell
  # matches the resolved path. Profile hosts are open to every program.
  egress_hosts = local.custom ? local.custom_hosts : local.profile.hosts
  egress_ports = local.custom ? local.custom_ports : [443]
  policy = yamlencode({
    version = 1
    filesystem_policy = {
      include_workdir = true
      read_only       = ["/bin", "/sbin", "/usr", "/lib", "/lib64", "/etc", "/opt", "/proc", "/sys", "/dev/urandom", "/var"]
      read_write      = ["/tmp", "/dev/null", "/dev/pts", "/dev/ptmx", "/dev/tty"]
    }
    network_policies = merge(
      {
        coder = {
          endpoints = [{ host = local.access_url.host, port = local.access_port }]
          binaries = [
            { path = "/usr/local/bin/coder" },
            { path = "/opt/claude/**" },
          ]
        }
      },
      length(local.egress_hosts) > 0 ? {
        profile = {
          endpoints = flatten([for h in local.egress_hosts : [for p in local.egress_ports : { host = h, port = p }]])
          binaries  = [{ path = "/**" }]
        }
      } : {}
    )
  })

  # Mounting the home disk under /sandbox replaces the volume that OpenShell
  # creates otherwise, so Coder owns the only disk.
  driver_config = jsonencode({
    kubernetes = merge(
      {
        volumes = [{
          name                    = "home"
          persistent_volume_claim = { claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name, read_only = false }
        }]
        containers = {
          agent = {
            volume_mounts = [{ name = "home", mount_path = local.home, read_only = false }]
          }
        }
      },
      local.runtime != "none" ? { pod = { runtime_class_name = local.runtime } } : {}
    )
  })
  # Copy the image's dotfiles into a new, empty home, then start the agent
  # as the main process of the sandbox.
  agent_command = "[ -e ${local.home}/.bashrc ] || cp -an /etc/skel/. ${local.home}/ 2>/dev/null || true; exec /usr/local/bin/coder agent"

}

resource "coder_agent" "dev" {
  os   = "linux"
  arch = "amd64"
  dir  = local.home

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
  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path ${local.home}"
    interval     = 60
    timeout      = 1
  }
  metadata {
    display_name = "Kernel"
    key          = "3_kernel"
    script       = "uname -r"
    interval     = 600
    timeout      = 1
  }
}

# The same check as custom_problems, for builds that do not come from the
# form, such as the API or the CLI.
resource "terraform_data" "custom_check" {
  count = local.custom ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.custom_problems == 0
      error_message = "Custom needs at least one valid host name and one port. Not valid: ${join(", ", local.custom_bad)}"
    }
  }
}

# Coder owns the home disk, so it outlives the sandbox. The labels let
# OpenShell attach it.
resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "${local.name}-home"
    namespace = var.namespace
    labels = merge(local.labels, {
      "openshell.ai/sandbox-attachable"           = "true"
      "openshell.ai/sandbox-attachable-workspace" = var.openshell_workspace
    })
    annotations = local.owner_annotations
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name != "" ? var.storage_class_name : null
    resources {
      requests = {
        storage = "${var.home_disk_size}Gi"
      }
    }
  }
}

# Only while the workspace is started. The launcher reads the agent token
# from it, so the token is not in the launcher Pod spec. OpenShell puts it
# in the sandbox Pod spec.
resource "kubernetes_secret_v1" "agent_token" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "${local.name}-agent-token"
    namespace = var.namespace
    labels    = local.labels
  }
  data = {
    token = coder_agent.dev.token
  }
}

# Terraform cannot call the OpenShell gateway, so a small launcher Pod
# creates the sandbox when the workspace starts and deletes it when the
# workspace stops. The gateway creates the sandbox Pods.
resource "kubernetes_pod_v1" "launcher" {
  count      = data.coder_workspace.me.start_count
  depends_on = [terraform_data.custom_check]

  metadata {
    name      = "${local.name}-launcher"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    automount_service_account_token = false
    enable_service_links            = false
    # The launcher deletes the sandbox on SIGTERM, which took about 37 s.
    termination_grace_period_seconds = 120
    # A restarted launcher replaces the sandbox, so a crash costs the
    # running session but not the home.
    restart_policy = "Always"
    security_context {
      run_as_non_root = true
      run_as_user     = 1000
      run_as_group    = 1000
      seccomp_profile {
        type = "RuntimeDefault"
      }
    }
    container {
      name              = "launcher"
      image             = var.launcher_image
      image_pull_policy = "IfNotPresent"
      command           = ["sh", "-c", file("${path.module}/launcher.sh")]
      security_context {
        allow_privilege_escalation = false
        read_only_root_filesystem  = true
        capabilities {
          drop = ["ALL"]
        }
      }
      dynamic "env" {
        for_each = {
          HOME                  = "/tmp/launcher"
          OPENSHELL_GATEWAY_URL = var.openshell_gateway_url
          OPENSHELL_WORKSPACE   = var.openshell_workspace
          SANDBOX_NAME          = local.sandbox_name
          SANDBOX_IMAGE         = var.workspace_image
          SANDBOX_CPU           = var.cpu
          SANDBOX_MEMORY        = var.memory
          SANDBOX_POLICY        = local.policy
          SANDBOX_DRIVER_CONFIG = local.driver_config
          SANDBOX_HOME          = local.home
          SANDBOX_COMMAND       = local.agent_command
          CODER_WORKSPACE_ID    = data.coder_workspace.me.id
          CODER_AGENT_URL       = data.coder_workspace.me.access_url
        }
        content {
          name  = env.key
          value = env.value
        }
      }
      env {
        name = "CODER_AGENT_TOKEN"
        value_from {
          secret_key_ref {
            name = kubernetes_secret_v1.agent_token[0].metadata[0].name
            key  = "token"
          }
        }
      }
      resources {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
      volume_mount {
        name       = "openshell-tls"
        mount_path = "/openshell-tls"
        read_only  = true
      }
      volume_mount {
        name       = "tmp"
        mount_path = "/tmp"
      }
    }
    volume {
      name = "openshell-tls"
      # cluster/ creates it with this name.
      secret {
        secret_name = "openshell-launcher-tls"
      }
    }
    volume {
      name = "tmp"
      empty_dir {}
    }
  }
}

# code-server and Claude Code are in the image, so the modules download
# nothing and work in Fully isolated.
module "code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "1.6.0"
  agent_id       = coder_agent.dev.id
  folder         = local.home
  offline        = true
  install_prefix = "/opt/code-server"
  order          = 1
}

# A prebuild clones the repository before anyone claims it, and the module
# skips the clone when the folder exists, so a claim does not wait for it.
module "git-clone" {
  count    = data.coder_workspace.me.start_count != 0 && var.git_repo_url != "" && contains(local.github_profiles, data.coder_parameter.network_isolation.value) ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.dev.id
  url      = var.git_repo_url
  base_dir = local.home
}

# Claude Code is in the image, so the template only sets its environment.
# The claude-code registry module does the same, but it reads the
# deprecated coder_task data source, which adds a warning to every build.
resource "coder_env" "claude_disable_autoupdater" {
  count    = var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}

# With the AI Gateway, Claude Code reaches Anthropic through the Coder
# server. It does not get the owner's session token, which has full access
# to the Coder API. The build uses that token once to create a token with
# only the user:read_personal scope, which the AI Gateway accepts, and gives
# the workspace that one. timestamp() defers the request to apply, so a plan
# creates nothing, and a prebuild gets its token when it is claimed.
#
# Coder deletes the session token before a stop build, so Terraform cannot
# revoke the scoped token on stop. It expires after the deployment's
# default token lifetime, and each start creates a new one.
locals {
  mint_ai_gateway_token = (
    var.enable_ai_gateway && var.enable_claude_code &&
    data.coder_workspace.me.start_count > 0 &&
    !data.coder_workspace.me.is_prebuild &&
    data.coder_workspace_owner.me.session_token != ""
  )
}

data "http" "ai_gateway_token" {
  count  = local.mint_ai_gateway_token ? 1 : 0
  url    = "${data.coder_workspace.me.access_url}/api/v2/users/me/keys/tokens"
  method = "POST"
  request_headers = {
    "Coder-Session-Token" = data.coder_workspace_owner.me.session_token
    "Content-Type"        = "application/json"
  }
  request_body = jsonencode({
    token_name = "ai-gateway-${substr(data.coder_workspace.me.id, 0, 8)}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
    scopes     = ["user:read_personal"]
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 201
      error_message = "Could not create the AI Gateway token: HTTP ${self.status_code}."
    }
  }
}

resource "coder_env" "anthropic_base_url" {
  count    = var.enable_ai_gateway && var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

resource "coder_env" "anthropic_auth_token" {
  count    = local.mint_ai_gateway_token ? 1 : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = sensitive(jsondecode(data.http.ai_gateway_token[0].response_body).key)
}

# Opens Claude Code in the home. It continues the last conversation in this
# folder, or starts a new one if there is none. In tmux, if the image has
# it, the session outlives the browser tab.
resource "coder_app" "claude" {
  count        = var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.dev.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  order        = 2
  command      = <<-EOT
    cd ${local.home}
    run="/opt/claude/bin/claude --continue || /opt/claude/bin/claude"
    if command -v tmux >/dev/null 2>&1; then
      exec tmux new-session -A -s claude "$run"
    fi
    eval "$run"
  EOT
}
