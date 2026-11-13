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
  description = "The Kubernetes namespace for workspaces. cluster/ creates it with the Role."
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

variable "proxy_image" {
  description = "The egress proxy image. Build it from build/egress-proxy/Dockerfile. Use a fixed tag or a digest, not :latest."
  type        = string

  validation {
    condition = (
      length(trimspace(var.proxy_image)) > 0 &&
      !endswith(var.proxy_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.proxy_image), length(split("/", var.proxy_image)) - 1)))
    )
    error_message = "proxy_image must have a tag other than :latest, or a digest, such as registry.example.com/coder/egress-proxy:v1."
  }
}

variable "coder_egress_cidrs" {
  description = "The IPv4 CIDR ranges of the Coder server, for example [\"203.0.113.10/32\"]. Every workspace can reach these ranges directly. Everything else goes through the proxy."
  type        = list(string)

  validation {
    condition     = length(var.coder_egress_cidrs) > 0 && alltrue([for c in var.coder_egress_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "coder_egress_cidrs must have at least one valid IPv4 CIDR range, such as 203.0.113.10/32."
  }
}

# 0, not null, so that coder templates push does not ask for it.
variable "coder_egress_port" {
  description = "The TCP port that workspaces use to reach the Coder server. 0 uses the port of the access URL: its explicit port, or 443 for https and 80 for http."
  type        = number
  default     = 0

  validation {
    condition     = var.coder_egress_port >= 0 && var.coder_egress_port <= 65535 && floor(var.coder_egress_port) == var.coder_egress_port
    error_message = "coder_egress_port must be 0 or a whole number from 1 to 65535."
  }
}

variable "coder_host_ip" {
  description = "The IPv4 address of the Coder access URL host. Workspaces have no DNS, so if the access URL uses a host name, the template adds this address to /etc/hosts. Leave empty if the access URL uses an IP address."
  type        = string
  default     = ""

  validation {
    condition     = var.coder_host_ip == "" || (can(cidrhost("${var.coder_host_ip}/32", 0)) && !strcontains(var.coder_host_ip, ":"))
    error_message = "coder_host_ip must be empty or an IPv4 address."
  }
}

# A comma-separated string, not a list, because Coder checks presets with
# every template variable as a string.
variable "runtimes" {
  description = "Sandbox runtimes that users can pick in addition to the node's container runtime, comma-separated. Offer only RuntimeClasses that the cluster has: gvisor, kata-qemu, kata-clh. Empty offers none."
  type        = string
  default     = ""

  validation {
    condition = (
      length(compact(split(",", replace(var.runtimes, " ", "")))) == length(distinct(compact(split(",", replace(var.runtimes, " ", ""))))) &&
      alltrue([for r in compact(split(",", replace(var.runtimes, " ", ""))) : contains(["gvisor", "kata-qemu", "kata-clh"], r)])
    )
    error_message = "runtimes can list only gvisor, kata-qemu, and kata-clh, comma-separated, each once."
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
  description = "A Git repository to clone into /home/coder over HTTPS, for example https://github.com/coder/coder. Only profiles that allow GitHub clone it. Empty clones nothing."
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

variable "network_policy_gate" {
  description = "Start the Coder agent only after the NetworkPolicy blocks the Kubernetes API server. Turn this off only if coder_egress_cidrs includes the API server address."
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "The DNS servers that the proxy uses, comma-separated IPv4 addresses. Empty uses 8.8.8.8 and 1.1.1.1. Use servers outside the cluster, because on some network plugins an ipBlock rule does not match cluster DNS. Workspaces have no DNS."
  type        = string
  default     = ""

  validation {
    condition     = alltrue([for d in compact(split(",", replace(var.dns_servers, " ", ""))) : can(cidrhost("${d}/32", 0)) && !strcontains(d, ":")])
    error_message = "dns_servers must be empty or IPv4 addresses, comma-separated."
  }
}

provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Network profiles: what a workspace can reach in addition to the Coder
# server. The proxy matches host names. Do not add hosts that store user
# content, because the workspace can send data to them.
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
      description  = "Coder only. No proxy, no internet, and no DNS."
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
    internet = {
      display_name = "Public internet"
      description  = "Coder and any public host name on ports 443 and 80. No raw IP addresses, private ranges, or cloud metadata."
      icon         = "/emojis/1f310.png"
      hosts        = []
    }
    custom = {
      display_name = "Custom"
      description  = "Coder and the host names and ports that you type below."
      icon         = "/emojis/270f.png"
      hosts        = []
    }
  }

  # Private, shared, and link-local ranges: the VPC, the cluster, other
  # Pods, and cloud metadata. The proxy cannot reach them.
  private_cidrs = ["10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"]
  dns_servers   = var.dns_servers != "" ? compact(split(",", replace(var.dns_servers, " ", ""))) : ["8.8.8.8", "1.1.1.1"]

  # Profiles that can reach GitHub, so they clone git_repo_url.
  github_profiles = ["github", "development", "internet"]

  runtimes = compact(split(",", replace(var.runtimes, " ", "")))
  runtime_options = {
    gvisor = {
      name        = "gVisor"
      description = "A kernel that runs in user space. Needs gVisor on the nodes."
      icon        = "/icon/container.svg"
    }
    kata-qemu = {
      name        = "Kata microVM (QEMU)"
      description = "A small VM with its own kernel. Needs a node with /dev/kvm."
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
  description  = "What the workspace can reach in addition to Coder. A proxy allows it by host name, and a NetworkPolicy lets the workspace reach only Coder and that proxy. You cannot change it after create."
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

  # An exact name with a dot, or "*." and at least two more labels. No IP
  # addresses, and no cluster or internal suffixes.
  host_label       = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
  host_pattern     = "^(\\*\\.)?(${local.host_label}\\.)+[a-z][a-z0-9-]*[a-z0-9]$"
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
  description  = "Type a host name such as api.example.com or *.example.com and press Enter. *.example.com also allows example.com."
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
  description  = "The ports that the workspace can use on the hosts above. The proxy relays HTTPS without decrypting it."
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
    error = length(local.custom_hosts) == 0 ? "Type at least one host name." : length(local.custom_ports) == 0 ? "Pick at least one port." : "Not a host name that the proxy can allow: ${join(", ", local.custom_bad)}."
  }
}

data "coder_parameter" "runtime" {
  count        = length(local.runtimes) > 0 ? 1 : 0
  name         = "runtime"
  display_name = "Kernel isolation"
  description  = "The RuntimeClass of the workspace Pod. The network rules are the same for every option."
  type         = "string"
  form_type    = "dropdown"
  default      = "none"
  mutable      = false
  order        = 5

  option {
    name        = "None"
    value       = "none"
    description = "The node's container runtime. The workspace shares the node kernel. The fastest."
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

  # What the proxy allows. Fully isolated has no proxy.
  any_host    = data.coder_parameter.network_isolation.value == "internet"
  proxy_hosts = local.custom ? local.custom_hosts : local.profile.hosts
  proxy       = local.any_host || length(local.proxy_hosts) > 0
  proxy_ports = local.custom ? local.custom_ports : local.any_host ? [443, 80] : [443]
  # Squid writes "*.example.com" as ".example.com", which also allows
  # example.com.
  squid_conf = templatefile("${path.module}/squid.conf.tftpl", {
    any_host        = local.any_host
    allowed_domains = join(" ", [for h in local.proxy_hosts : startswith(h, "*.") ? substr(h, 1, -1) : h])
    allow_tls       = contains(local.proxy_ports, 443)
    allow_http      = contains(local.proxy_ports, 80)
    dns_servers     = join(" ", local.dns_servers)
  })

  # Labels stay the same when a prebuilt workspace is claimed, so a claim
  # does not change the Pods.
  labels = {
    "app.kubernetes.io/name"    = "coder-workspace"
    "app.kubernetes.io/part-of" = "coder"
    "com.coder.resource"        = "true"
    "com.coder.workspace.id"    = data.coder_workspace.me.id
  }
  workspace_labels = merge(local.labels, { "coder.com/role" = "workspace" })
  proxy_labels     = merge(local.labels, { "coder.com/role" = "proxy" })
  owner_annotations = {
    "com.coder.workspace.name" = data.coder_workspace.me.name
    "com.coder.user.id"        = data.coder_workspace_owner.me.id
    "com.coder.user.username"  = data.coder_workspace_owner.me.name
  }

  access_host       = try(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)", data.coder_workspace.me.access_url)[0], "")
  access_host_is_ip = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", local.access_host))
  access_port = try(
    tonumber(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/:]+:([0-9]+)", data.coder_workspace.me.access_url)[0]),
    startswith(lower(data.coder_workspace.me.access_url), "http://") ? 80 : 443,
  )
  coder_port = var.coder_egress_port > 0 ? var.coder_egress_port : local.access_port

  # Copy the image's dotfiles into a new, empty home.
  seed_home = "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/. /home/coder/ 2>/dev/null || true"

  agent_command = join("\n", [
    local.seed_home,
    "ulimit -n 65536 2>/dev/null || true",
    var.network_policy_gate ? file("${path.module}/start-agent.sh") : "exec /usr/local/bin/coder agent",
  ])

  resources = {
    requests = { cpu = "500m", memory = "1Gi" }
    limits   = { cpu = "2", memory = "4Gi" }
  }
}

resource "coder_agent" "dev" {
  os   = "linux"
  arch = "amd64"

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
    script       = "coder stat disk --path $${HOME}"
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

# For the life of the workspace: the home disk, the network rules, and the
# proxy's config and Service.
resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name        = "${local.name}-home"
    namespace   = var.namespace
    labels      = local.labels
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

# The workspace Pod: no ingress, and egress only to the Coder server and
# its own proxy. No DNS, because the proxy resolves names.
resource "kubernetes_network_policy_v1" "workspace" {
  metadata {
    name      = "${local.name}-workspace"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = local.workspace_labels
    }
    policy_types = ["Ingress", "Egress"]

    egress {
      dynamic "to" {
        for_each = var.coder_egress_cidrs
        content {
          ip_block {
            cidr = to.value
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = tostring(local.coder_port)
      }
    }

    dynamic "egress" {
      for_each = local.proxy ? [1] : []
      content {
        to {
          pod_selector {
            match_labels = local.proxy_labels
          }
        }
        ports {
          protocol = "TCP"
          port     = "3128"
        }
      }
    }
  }
}

# The proxy Pod: ingress only from its workspace, and egress only to public
# addresses on the profile's ports and to DNS. Squid also refuses private
# addresses itself.
resource "kubernetes_network_policy_v1" "proxy" {
  count = local.proxy ? 1 : 0
  metadata {
    name      = "${local.name}-proxy"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = local.proxy_labels
    }
    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = local.workspace_labels
        }
      }
      ports {
        protocol = "TCP"
        port     = "3128"
      }
    }

    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = local.private_cidrs
        }
      }
      dynamic "ports" {
        for_each = local.proxy_ports
        content {
          protocol = "TCP"
          port     = tostring(ports.value)
        }
      }
    }

    egress {
      dynamic "to" {
        for_each = local.dns_servers
        content {
          ip_block {
            cidr = "${to.value}/32"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }
}

resource "kubernetes_config_map_v1" "proxy" {
  count = local.proxy ? 1 : 0
  metadata {
    name      = "${local.name}-proxy"
    namespace = var.namespace
    labels    = local.labels
  }
  data = {
    "squid.conf" = local.squid_conf
  }
}

# The workspace has no DNS, so it reaches the proxy by the Service's
# cluster IP. The IP stays the same for the life of the workspace.
resource "kubernetes_service_v1" "proxy" {
  count = local.proxy ? 1 : 0
  metadata {
    name      = "${local.name}-proxy"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = local.proxy_labels
    port {
      name        = "squid"
      port        = 3128
      target_port = 3128
    }
  }
}

# Only while the workspace is started. The Pod reads the agent token from
# it, so the token is not in the Pod spec.
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

# A new id on every start. VPC CNI groups Pods by their name without the
# last "-" part and drops a group's rules when an old Pod of the group is
# deleted. A fixed "-pod" after this id keeps every Pod in its own group.
resource "terraform_data" "pod_name" {
  count = data.coder_workspace.me.start_count
}

locals {
  pod_id = try(substr(terraform_data.pod_name[0].id, 0, 8), "")
  # curl reads only the lowercase names. Go and most other tools read the
  # uppercase ones.
  proxy_url = local.proxy ? "http://${kubernetes_service_v1.proxy[0].spec[0].cluster_ip}:3128" : ""
  proxy_env = local.proxy ? {
    HTTP_PROXY  = local.proxy_url
    HTTPS_PROXY = local.proxy_url
    http_proxy  = local.proxy_url
    https_proxy = local.proxy_url
    NO_PROXY    = "localhost,127.0.0.1,::1,${local.access_host}"
    no_proxy    = "localhost,127.0.0.1,::1,${local.access_host}"
  } : {}
}

# Only while the workspace is started, like the workspace Pod. Squid reads
# its config only at start, so a new config replaces the Pod.
resource "kubernetes_pod_v1" "proxy" {
  count      = local.proxy ? data.coder_workspace.me.start_count : 0
  depends_on = [kubernetes_network_policy_v1.proxy]

  lifecycle {
    replace_triggered_by = [kubernetes_config_map_v1.proxy]
  }
  metadata {
    name      = "${local.name}-proxy-${local.pod_id}-pod"
    namespace = var.namespace
    labels    = local.proxy_labels
  }
  spec {
    automount_service_account_token  = false
    enable_service_links             = false
    termination_grace_period_seconds = 1
    security_context {
      run_as_non_root = true
      run_as_user     = 31
      run_as_group    = 31
      seccomp_profile {
        type = "RuntimeDefault"
      }
    }
    container {
      name              = "squid"
      image             = var.proxy_image
      image_pull_policy = "IfNotPresent"
      security_context {
        allow_privilege_escalation = false
        read_only_root_filesystem  = true
        capabilities {
          drop = ["ALL"]
        }
      }
      resources {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      readiness_probe {
        tcp_socket {
          port = 3128
        }
        period_seconds = 2
      }
      volume_mount {
        name       = "conf"
        mount_path = "/etc/squid-conf"
        read_only  = true
      }
    }
    volume {
      name = "conf"
      config_map {
        name = kubernetes_config_map_v1.proxy[0].metadata[0].name
      }
    }
  }
}

# A bare Pod, so nothing waits on a controller. Stop deletes it and keeps
# the home disk.
resource "kubernetes_pod_v1" "workspace" {
  count      = data.coder_workspace.me.start_count
  depends_on = [kubernetes_network_policy_v1.workspace]

  lifecycle {
    precondition {
      condition     = local.access_host_is_ip || var.coder_host_ip != ""
      error_message = "Workspaces have no DNS, so the agent cannot resolve ${local.access_host}. Set the coder_host_ip template variable to the IP address of the Coder server."
    }
  }

  metadata {
    name      = "${local.name}-${local.pod_id}-pod"
    namespace = var.namespace
    labels    = local.workspace_labels
  }
  spec {
    runtime_class_name               = local.runtime == "none" ? null : local.runtime
    automount_service_account_token  = false
    enable_service_links             = false
    termination_grace_period_seconds = 2
    dns_policy                       = "None"
    # No DNS: lookups go to a closed local port and fail at once. The proxy
    # resolves names.
    dns_config {
      nameservers = ["127.0.0.1"]
    }
    dynamic "host_aliases" {
      for_each = var.coder_host_ip != "" && !local.access_host_is_ip ? [1] : []
      content {
        ip        = var.coder_host_ip
        hostnames = [local.access_host]
      }
    }
    security_context {
      run_as_non_root        = true
      run_as_user            = 1000
      run_as_group           = 1000
      fs_group               = 1000
      fs_group_change_policy = "OnRootMismatch"
      seccomp_profile {
        type = "RuntimeDefault"
      }
    }
    container {
      name              = "dev"
      image             = var.workspace_image
      image_pull_policy = "IfNotPresent"
      command           = ["bash", "-c", local.agent_command]
      working_dir       = "/home/coder"
      env {
        name = "CODER_AGENT_TOKEN"
        value_from {
          secret_key_ref {
            name = kubernetes_secret_v1.agent_token[0].metadata[0].name
            key  = "token"
          }
        }
      }
      env {
        name  = "CODER_AGENT_URL"
        value = data.coder_workspace.me.access_url
      }
      env {
        name  = "CODER_AGENT_AUTH"
        value = "token"
      }
      dynamic "env" {
        for_each = local.proxy_env
        content {
          name  = env.key
          value = env.value
        }
      }
      security_context {
        allow_privilege_escalation = false
        run_as_non_root            = true
        capabilities {
          drop = ["ALL"]
        }
      }
      resources {
        requests = local.resources.requests
        limits   = local.resources.limits
      }
      volume_mount {
        name       = "home"
        mount_path = "/home/coder"
      }
      volume_mount {
        name       = "tmp"
        mount_path = "/tmp"
      }
    }
    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
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
  folder         = "/home/coder"
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
  base_dir = "/home/coder"
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

# Opens Claude Code in /home/coder. It continues the last conversation in
# this folder, or starts a new one if there is none. In tmux, if the image
# has it, the session outlives the browser tab.
resource "coder_app" "claude" {
  count        = var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.dev.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  order        = 2
  command      = <<-EOT
    cd /home/coder
    run="/opt/claude/bin/claude --continue || /opt/claude/bin/claude"
    if command -v tmux >/dev/null 2>&1; then
      exec tmux new-session -A -s claude "$run"
    fi
    eval "$run"
  EOT
}
