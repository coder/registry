terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    # A small REST provider instead of hashicorp/kubernetes. It starts much
    # faster, and Terraform is most of the time of a prebuild claim.
    restapi = {
      source  = "Mastercard/restapi"
      version = "3.0.0"
    }
  }
}

# The workspace runs as an Agent Substrate actor in a Cloud Hypervisor
# microVM, on a separate Kubernetes cluster. Terraform writes only two
# objects to the Coder cluster, and coder-bridge in the Substrate cluster
# does the rest:
#
#   - a ConfigMap for the life of the workspace, with the network profile.
#     coder-bridge creates the actor and its egress policy, and deletes the
#     actor when the ConfigMap goes away.
#   - a Secret with the agent token while the workspace is started.
#     coder-bridge resumes the actor while it exists and suspends it when it
#     goes away. A suspended actor keeps its memory and files.

variable "namespace" {
  type        = string
  description = "Namespace in the Coder cluster that coder-bridge reads. Create it with cluster/coder-cluster.yaml."
  default     = "coder-substrate"
  validation {
    condition     = trimspace(var.namespace) != ""
    error_message = "namespace must not be empty."
  }
}

variable "prebuild_instances" {
  type        = number
  description = "Prebuilt workspaces for each preset. Each one keeps a Substrate worker busy. Prebuilds need Coder Premium. Set to 0 to turn them off."
  default     = 1
  validation {
    condition     = var.prebuild_instances >= 0 && floor(var.prebuild_instances) == var.prebuild_instances
    error_message = "prebuild_instances must be a whole number of at least 0."
  }
}

variable "kube_api_url" {
  type        = string
  description = "Kubernetes API of the Coder cluster. The default is the in-cluster address, for a provisioner that runs in the Coder cluster."
  default     = "https://kubernetes.default.svc"
}

variable "kube_token_path" {
  type        = string
  description = "File with the token that the provisioner uses for the Kubernetes API."
  default     = "/var/run/secrets/kubernetes.io/serviceaccount/token"
}

variable "kube_ca_path" {
  type        = string
  description = "File with the CA certificate of the Kubernetes API."
  default     = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
}

data "coder_workspace" "me" {}
data "coder_provisioner" "me" {}

provider "restapi" {
  uri                  = var.kube_api_url
  root_ca_file         = var.kube_ca_path
  write_returns_object = true
  headers = {
    Authorization = sensitive("Bearer ${trimspace(file(var.kube_token_path))}")
  }
}

locals {
  github_hosts = [
    "github.com",                           # git clone
    "api.github.com",                       # gh CLI
    "codeload.github.com",                  # archive downloads
    "objects.githubusercontent.com",        # release downloads
    "raw.githubusercontent.com",            # raw file reads
    "release-assets.githubusercontent.com", # release downloads
  ]

  # What a workspace can reach in addition to Coder. Substrate rules name
  # host names only, so there is no Public internet profile. Do not add
  # hosts that store user content, because the workspace can send data to
  # them.
  profiles = {
    "isolated" = {
      display_name = "Fully isolated"
      description  = "Coder only. No internet and no DNS. For untrusted code and sensitive data."
      icon         = "/emojis/1f512.png"
      hosts        = []
      custom       = false
    }
    "github" = {
      display_name = "GitHub only"
      description  = "Coder and GitHub. For bots that read a repo and comment on PRs."
      icon         = "/icon/github.svg"
      hosts        = local.github_hosts
      custom       = false
    }
    "development" = {
      display_name = "GitHub and package registries"
      description  = "Coder, GitHub, npm, the Go module proxy, and PyPI. For builds and tests."
      icon         = "/emojis/1f4e6.png"
      hosts = concat(local.github_hosts, [
        "registry.npmjs.org",
        "proxy.golang.org",
        "sum.golang.org",
        "storage.googleapis.com",
        "pypi.org",
        "files.pythonhosted.org",
      ])
      custom = false
    }
    "custom" = {
      display_name = "Custom"
      description  = "Coder and the host names and ports that you type below."
      icon         = "/emojis/270f.png"
      hosts        = []
      custom       = true
    }
  }
}

data "coder_parameter" "network_isolation" {
  name         = "network_isolation"
  display_name = "Network isolation"
  description  = "What the workspace can reach in addition to Coder. The Substrate egress gateway enforces it by host name, outside the microVM. Everything else, UDP included, is blocked. You cannot change it after create."
  type         = "string"
  form_type    = "dropdown"
  default      = "isolated"
  # Immutable, so a workspace cannot widen its own network access.
  mutable = false
  order   = 1

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

locals {
  profile = local.profiles[data.coder_parameter.network_isolation.value]
  actor   = "ws-${data.coder_workspace.me.id}"

  custom       = local.profile.custom
  custom_hosts = local.custom ? distinct([for h in jsondecode(data.coder_parameter.custom_hosts[0].value) : lower(trimspace(h)) if trimspace(h) != ""]) : []
  custom_ports = local.custom ? [for p in jsondecode(data.coder_parameter.custom_ports[0].value) : tonumber(p)] : []

  # A host is an exact name with a dot, or "*." and at least two more
  # labels. Substrate accepts no other wildcard and no IP address. Cluster
  # and internal suffixes are blocked, because the gateway resolves names
  # in the cluster.
  host_label       = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
  host_pattern     = "^(\\*\\.)?(${local.host_label}\\.)+[a-z][a-z0-9-]*[a-z0-9]$"
  blocked_suffixes = ["localhost", "local", "internal", "cluster.local", "svc", "localdomain"]
  custom_bad = [
    for h in local.custom_hosts : h
    if !can(regex(local.host_pattern, h)) ||
    anytrue([for b in local.blocked_suffixes : h == b || endswith(h, ".${b}")])
  ]
  custom_problems = local.custom ? length(local.custom_bad) + (length(local.custom_hosts) == 0 ? 1 : 0) + (length(local.custom_ports) == 0 ? 1 : 0) : 0

  egress_hosts = local.custom ? local.custom_hosts : local.profile.hosts
  egress_ports = local.custom ? local.custom_ports : [443]

  # No owner or workspace name: they change when someone claims a prebuild,
  # and an update there would add API calls to the claim.
  labels = {
    "app.kubernetes.io/part-of" = "coder-substrate"
    "coder.com/actor"           = local.actor
    "com.coder.workspace.id"    = data.coder_workspace.me.id
  }
}

data "coder_parameter" "custom_hosts" {
  count        = local.custom ? 1 : 0
  name         = "custom_hosts"
  display_name = "Custom: host names"
  description  = "Starts with GitHub and npm. Remove what you do not need, or type a host name such as api.example.com or *.example.com and press Enter."
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
  description  = "The ports that the workspace can use on the hosts above. Substrate passes HTTPS through without decrypting it. It blocks protocols where the server speaks first, such as SSH."
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
}

# The number of problems in the Custom fields. It appears only while there
# is one, and its validation blocks Create.
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
    error = length(local.custom_hosts) == 0 ? "Type at least one host name." : length(local.custom_ports) == 0 ? "Pick at least one port." : "Not a host name that Substrate can allow: ${join(", ", local.custom_bad)}."
  }
}

resource "terraform_data" "custom_check" {
  count = local.custom ? 1 : 0
  lifecycle {
    precondition {
      condition     = local.custom_problems == 0
      error_message = "Custom needs at least one valid host name and one port. Not valid: ${join(", ", local.custom_bad)}"
    }
  }
}

resource "coder_agent" "dev" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  dir  = "/home/coder"

  metadata {
    display_name = "Kernel"
    key          = "0_kernel"
    script       = "uname -r"
    interval     = 600
    timeout      = 5
  }
  metadata {
    display_name = "CPU Usage"
    key          = "1_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "RAM Usage"
    key          = "2_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

# For the life of the workspace. coder-bridge creates the actor and its
# egress policy from it.
resource "restapi_object" "workspace" {
  depends_on                = [terraform_data.custom_check]
  path                      = "/api/v1/namespaces/${var.namespace}/configmaps"
  id_attribute              = "metadata/name"
  ignore_all_server_changes = true
  data = jsonencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata   = { name = local.actor, labels = local.labels }
    data = {
      hosts = jsonencode(local.egress_hosts)
      ports = jsonencode(local.egress_ports)
    }
  })
}

# Only while the workspace is started. coder-bridge resumes the actor and
# hands this token to it.
resource "restapi_object" "agent" {
  count                     = data.coder_workspace.me.start_count
  path                      = "/api/v1/namespaces/${var.namespace}/secrets"
  id_attribute              = "metadata/name"
  ignore_all_server_changes = true
  data = jsonencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = { name = "${local.actor}-agent", labels = local.labels }
    stringData = { token = coder_agent.dev.token }
  })
}

resource "coder_metadata" "workspace" {
  count       = data.coder_workspace.me.start_count
  resource_id = restapi_object.agent[0].id
  icon        = "/icon/memory.svg"
  item {
    key   = "actor"
    value = "coder/${local.actor}"
  }
  item {
    key   = "network"
    value = local.profile.display_name
  }
}

data "coder_workspace_preset" "profile" {
  for_each    = { for k, v in local.profiles : k => v if !v.custom }
  name        = each.value.display_name
  description = each.value.description
  icon        = each.value.icon
  default     = each.key == "isolated"
  parameters = {
    network_isolation = each.key
  }
  # A prebuild is a running actor with a connected agent. A claim keeps the
  # actor and the agent token, and the agent only reinitializes.
  dynamic "prebuilds" {
    for_each = var.prebuild_instances > 0 ? [1] : []
    content {
      instances = var.prebuild_instances
    }
  }
}
