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
  description = "The namespace for workspaces. cluster/ creates it with the Role."
  type        = string

  validation {
    condition     = length(trimspace(var.namespace)) > 0
    error_message = "namespace must not be empty."
  }
}

variable "workspace_image" {
  description = "The sandbox image. Build it from build/Dockerfile, with a Coder agent that matches your Coder server. The Docker daemon in the workspace Pod pulls it, so it must be public or readable with image_pull_secret. Use a fixed tag or a digest, not :latest."
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
  description = "The launcher image with the OpenShell gateway, the openshell CLI, and the Docker CLI. Build it from build/launcher/Dockerfile. Use a fixed tag or a digest, not :latest."
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

variable "docker_image" {
  description = "The Docker daemon image. Use a fixed tag or a digest, not :latest."
  type        = string
  default     = "docker:28-dind"

  validation {
    condition = (
      length(trimspace(var.docker_image)) > 0 &&
      !endswith(var.docker_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.docker_image), length(split("/", var.docker_image)) - 1)))
    )
    error_message = "docker_image must have a tag other than :latest, or a digest, such as docker:28-dind."
  }
}

variable "image_pull_secret" {
  description = "A kubernetes.io/dockerconfigjson Secret in the namespace, for a private workspace_image. The Docker daemon in the Pod pulls the image with it. Empty pulls without credentials."
  type        = string
  default     = ""
}

variable "coder_egress_cidrs" {
  description = "The IPv4 CIDR ranges of the Coder server, for example [\"203.0.113.10/32\"]. Set them if the Coder server has a private address, because the NetworkPolicy blocks private ranges."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.coder_egress_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "coder_egress_cidrs must be valid IPv4 CIDR ranges, such as 203.0.113.10/32."
  }
}

# A comma-separated string, not a list, because Coder checks presets with
# every template variable as a string.
variable "runtimes" {
  description = "The Kata runtimes that users can pick, comma-separated, in order. The first is the default: kata-clh, kata-qemu. The Docker daemon is privileged, so the template runs only in a microVM."
  type        = string
  default     = "kata-clh"

  validation {
    condition = (
      length(compact(split(",", replace(var.runtimes, " ", "")))) > 0 &&
      length(compact(split(",", replace(var.runtimes, " ", "")))) == length(distinct(compact(split(",", replace(var.runtimes, " ", ""))))) &&
      alltrue([for r in compact(split(",", replace(var.runtimes, " ", ""))) : contains(["kata-clh", "kata-qemu"], r)])
    )
    error_message = "runtimes must list one or more of kata-clh and kata-qemu, comma-separated, each once."
  }
}

variable "docker_disk_size" {
  description = "The size of the persistent Docker disk in GiB. It keeps the home, the images, and the gateway's images across stops."
  type        = number
  default     = 30

  validation {
    condition     = var.docker_disk_size >= 5
    error_message = "docker_disk_size must be at least 5."
  }
}

variable "storage_class_name" {
  description = "The StorageClass for the Docker disk. Leave empty to use the cluster default. It needs volumeMode Block, such as EBS, and volumeBindingMode WaitForFirstConsumer."
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

variable "network_policy_gate" {
  description = "Start the sandbox only after the NetworkPolicy blocks the Kubernetes API server. Turn this off only if the API server has a public address."
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
      description = "A small VM with its own kernel, around the Docker daemon and the OpenShell sandbox. Needs a node with /dev/kvm."
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
  name         = "runtime"
  display_name = "Kernel isolation"
  description  = "The Kata RuntimeClass of the workspace Pod. The Docker daemon is privileged inside the VM only. The network and file rules are the same for every option."
  type         = "string"
  form_type    = "dropdown"
  default      = local.runtimes[0]
  mutable      = false
  order        = 5

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

# One preset for each fixed profile, on the default runtime. A preset sets
# every immutable parameter, so a claimed prebuild never changes one.
data "coder_workspace_preset" "profile" {
  for_each    = { for k, v in local.profiles : k => v if k != "custom" }
  name        = each.value.display_name
  description = each.value.description
  icon        = each.value.icon
  default     = each.key == "isolated"
  parameters = {
    network_isolation = each.key
    runtime           = local.runtimes[0]
  }

  dynamic "prebuilds" {
    for_each = var.prebuild_instances > 0 ? [1] : []
    content {
      instances = var.prebuild_instances
    }
  }
}

locals {
  name    = "coder-${data.coder_workspace.me.id}"
  runtime = data.coder_parameter.runtime.value
  profile = local.profiles[data.coder_parameter.network_isolation.value]
  # OpenShell sandbox names have at most 19 characters.
  sandbox_name = "coder-${substr(replace(data.coder_workspace.me.id, "-", ""), 0, 13)}"
  home         = "/home/coder"

  # Labels stay the same when a prebuilt workspace is claimed, so a claim
  # does not change the Pod.
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
      read_write      = [local.home, "/tmp", "/dev/null", "/dev/pts", "/dev/ptmx", "/dev/tty"]
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

  # The home is a Docker volume on the Docker disk, which launcher.sh
  # creates. It is outside the image's workspace root, /sandbox, so it is
  # the only persistent path.
  driver_config = jsonencode({
    docker = {
      mounts = [{ type = "volume", source = "coder-home", target = local.home, read_only = false }]
    }
  })
  # Copy the image's dotfiles into a new, empty home, then start the agent
  # as the main process of the sandbox.
  agent_command = "[ -e ${local.home}/.bashrc ] || cp -an /etc/skel/. ${local.home}/ 2>/dev/null || true; exec /usr/local/bin/coder agent"

  # The Docker disk is formatted on first use only.
  docker_command = join("\n", [
    "set -e",
    "mkdir -p /var/lib/docker",
    "blkid /dev/docker-data | grep -q TYPE= || mkfs.ext4 -q -F /dev/docker-data",
    "mount /dev/docker-data /var/lib/docker",
    "exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker/docker.sock --group=1000",
  ])

  # Private, shared, and link-local ranges: the VPC, the cluster, other
  # Pods, and cloud metadata. The Pod cannot reach them.
  private_cidrs = ["10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"]
  # 443 for image pulls, the access URL port for the Coder server, and the
  # profile's ports for the supervisor. The OpenShell policy still limits
  # the hosts.
  public_ports = distinct(concat([443, local.access_port], local.egress_ports))

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

# The Docker disk is a raw block device. ext4 on it is local to the VM, so
# Docker can use overlay2. It keeps the home volume and the images across
# stops.
resource "kubernetes_persistent_volume_claim_v1" "docker" {
  metadata {
    name        = "${local.name}-docker"
    namespace   = var.namespace
    labels      = local.labels
    annotations = local.owner_annotations
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    volume_mode        = "Block"
    storage_class_name = var.storage_class_name != "" ? var.storage_class_name : null
    resources {
      requests = {
        storage = "${var.docker_disk_size}Gi"
      }
    }
  }
}

# No ingress. Egress to the Coder server, and to public addresses on the
# profile's ports and DNS, for the OpenShell supervisor and for image pulls.
# No private ranges, so no cluster, VPC, or cloud metadata. The sandbox
# itself has no network: only the supervisor connects, and only to the
# policy's hosts.
resource "kubernetes_network_policy_v1" "workspace" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = {
        "com.coder.workspace.id" = data.coder_workspace.me.id
      }
    }
    policy_types = ["Ingress", "Egress"]

    dynamic "egress" {
      for_each = length(var.coder_egress_cidrs) > 0 ? [1] : []
      content {
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
          port     = tostring(local.access_port)
        }
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
        for_each = local.public_ports
        content {
          protocol = "TCP"
          port     = tostring(ports.value)
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

# Only while the workspace is started. The launcher reads the agent token
# from it and passes it to the sandbox.
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

# One Kata microVM with two containers: a Docker daemon that is privileged
# inside the VM only, and the launcher with a standalone OpenShell gateway.
# The gateway's Docker driver runs the sandbox and its supervisor as Docker
# containers. Stop deletes the Pod and keeps the Docker disk.
resource "kubernetes_pod_v1" "workspace" {
  count      = data.coder_workspace.me.start_count
  depends_on = [terraform_data.custom_check, kubernetes_network_policy_v1.workspace]

  metadata {
    name      = "${local.name}-${substr(terraform_data.pod_name[0].id, 0, 8)}-pod"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    runtime_class_name               = local.runtime
    automount_service_account_token  = false
    enable_service_links             = false
    termination_grace_period_seconds = 5
    dns_policy                       = "None"
    dns_config {
      nameservers = ["8.8.8.8", "1.1.1.1"]
    }

    container {
      name              = "launcher"
      image             = var.launcher_image
      image_pull_policy = "IfNotPresent"
      command           = ["bash", "-c", file("${path.module}/launcher.sh")]
      security_context {
        run_as_user                = 1000
        run_as_group               = 1000
        run_as_non_root            = true
        allow_privilege_escalation = false
        capabilities {
          drop = ["ALL"]
        }
      }
      dynamic "env" {
        for_each = merge(
          {
            HOME                  = "/tmp/launcher"
            NETWORK_POLICY_GATE   = tostring(var.network_policy_gate)
            SANDBOX_NAME          = local.sandbox_name
            SANDBOX_IMAGE         = var.workspace_image
            SANDBOX_UID           = "1000"
            SANDBOX_POLICY        = local.policy
            SANDBOX_DRIVER_CONFIG = local.driver_config
            SANDBOX_HOME          = local.home
            SANDBOX_COMMAND       = local.agent_command
            CODER_AGENT_URL       = data.coder_workspace.me.access_url
          },
          var.image_pull_secret != "" ? { DOCKER_CONFIG = "/docker-config" } : {},
        )
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
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "1", memory = "512Mi" }
      }
      volume_mount {
        name       = "docker-socket"
        mount_path = "/var/run/docker"
      }
      volume_mount {
        name       = "tmp"
        mount_path = "/tmp"
      }
      dynamic "volume_mount" {
        for_each = var.image_pull_secret != "" ? [1] : []
        content {
          name       = "docker-config"
          mount_path = "/docker-config"
          read_only  = true
        }
      }
    }

    container {
      name              = "docker"
      image             = var.docker_image
      image_pull_policy = "IfNotPresent"
      command           = ["sh", "-c", local.docker_command]
      # No TLS listener on tcp/2376. Only the Unix socket is used.
      env {
        name  = "DOCKER_TLS_CERTDIR"
        value = ""
      }
      security_context {
        privileged = true
      }
      resources {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "4", memory = "6Gi" }
      }
      volume_device {
        name        = "docker-data"
        device_path = "/dev/docker-data"
      }
      volume_mount {
        name       = "docker-socket"
        mount_path = "/var/run/docker"
      }
    }

    volume {
      name = "docker-data"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.docker.metadata[0].name
      }
    }
    # In memory, so it lives inside the VM. A Unix socket does not work
    # across the virtio-fs share that Kata uses for a disk-backed emptyDir.
    volume {
      name = "docker-socket"
      empty_dir {
        medium     = "Memory"
        size_limit = "64Mi"
      }
    }
    volume {
      name = "tmp"
      empty_dir {}
    }
    dynamic "volume" {
      for_each = var.image_pull_secret != "" ? [1] : []
      content {
        name = "docker-config"
        secret {
          secret_name = var.image_pull_secret
          items {
            key  = ".dockerconfigjson"
            path = "config.json"
          }
        }
      }
    }
  }

  # A Kata RuntimeClass adds its node selector to the Pod. Without this, a
  # plan sees it as a change and replaces the Pod.
  lifecycle {
    ignore_changes = [spec[0].node_selector]
  }

  timeouts {
    create = "10m"
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
