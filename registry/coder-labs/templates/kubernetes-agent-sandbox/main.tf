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
  description = "The Kubernetes namespace for workspaces. cluster/ creates it with the Role and the warm pools."
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

variable "coder_egress_cidrs" {
  description = "The IPv4 CIDR ranges of the Coder server, for example [\"203.0.113.10/32\"]. Every workspace can reach these ranges, and nothing else in Fully isolated."
  type        = list(string)

  validation {
    condition     = length(var.coder_egress_cidrs) > 0 && alltrue([for c in var.coder_egress_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "coder_egress_cidrs must have at least one valid IPv4 CIDR range, such as 203.0.113.10/32."
  }
}

variable "coder_egress_port" {
  description = "The TCP port that workspaces use to reach the Coder server. Empty uses the port of the access URL: its explicit port, or 443 for https and 80 for http."
  type        = number
  default     = null

  validation {
    condition     = var.coder_egress_port == null ? true : (var.coder_egress_port >= 1 && var.coder_egress_port <= 65535 && floor(var.coder_egress_port) == var.coder_egress_port)
    error_message = "coder_egress_port must be empty or a whole number from 1 to 65535."
  }
}

# runtimes and scratch_profiles are comma-separated strings, not lists,
# because Coder checks presets with every template variable as a string.
variable "runtimes" {
  description = "The runtimes that users can pick, comma-separated, in order. The first is the default. Offer only RuntimeClasses that the cluster has: gvisor, kata-qemu, kata-clh."
  type        = string
  default     = "gvisor"

  validation {
    condition = (
      length(compact(split(",", replace(var.runtimes, " ", "")))) > 0 &&
      length(compact(split(",", replace(var.runtimes, " ", "")))) == length(distinct(compact(split(",", replace(var.runtimes, " ", ""))))) &&
      alltrue([for r in compact(split(",", replace(var.runtimes, " ", ""))) : contains(["gvisor", "kata-qemu", "kata-clh"], r)])
    )
    error_message = "runtimes must list one or more of gvisor, kata-qemu, and kata-clh, comma-separated, each once."
  }
}

variable "scratch_profiles" {
  description = "The network profiles that offer a scratch home, comma-separated: isolated, github, or both. Each needs the warm pools from cluster/ for every runtime. Empty turns off scratch homes."
  type        = string
  default     = "isolated,github"

  validation {
    condition = (
      length(compact(split(",", replace(var.scratch_profiles, " ", "")))) == length(distinct(compact(split(",", replace(var.scratch_profiles, " ", ""))))) &&
      alltrue([for p in compact(split(",", replace(var.scratch_profiles, " ", ""))) : contains(["isolated", "github"], p)])
    )
    error_message = "scratch_profiles can list only isolated and github, comma-separated, each once."
  }
}

variable "coder_host_ip" {
  description = "The IPv4 address of the Coder access URL host. Fully isolated blocks DNS, so if the access URL uses a host name, the template adds this address to /etc/hosts. Leave empty if the access URL uses an IP address."
  type        = string
  default     = ""

  validation {
    condition     = var.coder_host_ip == "" || (can(cidrhost("${var.coder_host_ip}/32", 0)) && !strcontains(var.coder_host_ip, ":"))
    error_message = "coder_host_ip must be empty or an IPv4 address."
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
  description = "The number of prebuilt workspaces to keep for each persistent preset. Prebuilds need a Coder Premium license. Set 0 to turn them off."
  type        = number
  default     = 1

  validation {
    condition     = var.prebuild_instances >= 0 && floor(var.prebuild_instances) == var.prebuild_instances
    error_message = "prebuild_instances must be a whole number, 0 or more."
  }
}

variable "git_repo_url" {
  description = "A Git repository to clone into /home/coder, for example https://github.com/coder/coder. Only GitHub only and Public internet workspaces clone it, because Fully isolated cannot reach Git hosts. Empty clones nothing."
  type        = string
  default     = ""
}

variable "enable_ai_gateway" {
  description = "Send Claude Code requests through the Coder AI Gateway (Premium). Claude Code then reaches Anthropic through the Coder server, so it works in Fully isolated."
  type        = bool
  default     = true
}

variable "network_policy_gate" {
  description = "Start the Coder agent only after the NetworkPolicy blocks the Kubernetes API server. Turn this off only if coder_egress_cidrs includes the API server address."
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "The DNS servers that workspaces use, comma-separated IPv4 addresses. Empty uses 8.8.8.8 and 1.1.1.1 from shared/defaults.json. Use servers that the GitHub only and Public internet profiles can reach."
  type        = string
  default     = ""

  validation {
    condition     = alltrue([for d in compact(split(",", replace(var.dns_servers, " ", ""))) : can(cidrhost("${d}/32", 0)) && !strcontains(d, ":")])
    error_message = "dns_servers must be empty or IPv4 addresses, comma-separated."
  }
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

# Network profiles. A NetworkPolicy matches IP ranges, not host names.
locals {
  runtimes         = compact(split(",", replace(var.runtimes, " ", "")))
  scratch_profiles = compact(split(",", replace(var.scratch_profiles, " ", "")))

  runtime_options = {
    gvisor = {
      name        = "gVisor"
      description = "A kernel that runs in user space. Runs on any node with gVisor installed."
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

  # shared/defaults.json is also read by cluster/main.tf. It has:
  #   github_cidrs: the large GitHub IPv4 ranges from
  #     https://api.github.com/meta (web, api, git). To refresh:
  #     curl -s https://api.github.com/meta | jq -r '.web+.api+.git|unique[]|select(test(":")|not)|select(endswith("/32")|not)'
  #   private_cidrs: the VPC, the cluster, other Pods, and cloud metadata.
  #     Public internet excludes them.
  #   dns_servers: the default DNS servers, unless var.dns_servers is set.
  #     Fully isolated cannot reach them, so lookups fail fast.
  #   resources: the Pod requests and limits.
  defaults      = jsondecode(file("${path.module}/shared/defaults.json"))
  github_cidrs  = local.defaults.github_cidrs
  private_cidrs = local.defaults.private_cidrs
  dns_servers   = var.dns_servers != "" ? compact(split(",", replace(var.dns_servers, " ", ""))) : local.defaults.dns_servers

  profiles = {
    isolated = {
      display_name = "Fully isolated"
      description  = "Coder only. No internet and no DNS."
      icon         = "/emojis/1f512.png"
      cidrs        = []
      except       = []
    }
    github = {
      display_name = "GitHub only"
      description  = "Coder, the GitHub IP ranges on ports 443 and 80, and public DNS."
      icon         = "/icon/github.svg"
      cidrs        = local.github_cidrs
      except       = []
    }
    internet = {
      display_name = "Public internet"
      description  = "Coder and every public IPv4 address on ports 443 and 80, and public DNS. No private ranges."
      icon         = "/emojis/1f310.png"
      cidrs        = ["0.0.0.0/0"]
      except       = local.private_cidrs
    }
  }
}

data "coder_parameter" "network_isolation" {
  name         = "network_isolation"
  display_name = "Network isolation"
  description  = "What the workspace can reach in addition to Coder. A Kubernetes NetworkPolicy enforces it by IP range. You cannot change it after create."
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

data "coder_parameter" "runtime" {
  name         = "runtime"
  display_name = "Kernel isolation"
  description  = "The RuntimeClass of the sandbox. The network rules are the same for every option."
  type         = "string"
  form_type    = "dropdown"
  default      = local.runtimes[0]
  mutable      = false
  order        = 2

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

# A pooled Pod shares network rules with the other Pods of its pool on the
# same node (Amazon VPC CNI), so each scratch profile has its own pool:
# coder-<runtime> for Fully isolated and coder-<runtime>-github for GitHub
# only. Public internet has no scratch home. cluster/main.tf creates the
# pools for scratch_profiles.
data "coder_parameter" "home" {
  name         = "home"
  display_name = "Home directory"
  description  = "Where /home/coder lives. You cannot change it after create."
  type         = "string"
  form_type    = "radio"
  default      = "persistent"
  mutable      = false
  order        = 3

  option {
    name        = "Persistent"
    value       = "persistent"
    description = "A disk at /home/coder that is kept when the workspace stops."
    icon        = "/emojis/1f4be.png"
  }
  dynamic "option" {
    for_each = contains(local.scratch_profiles, data.coder_parameter.network_isolation.value) ? [1] : []
    content {
      name        = "Scratch"
      value       = "scratch"
      description = "A booted sandbox from the warm pool. /home/coder is deleted when the workspace stops. Fully isolated or GitHub only."
      icon        = "/emojis/26a1.png"
    }
  }
}

data "coder_workspace_preset" "persistent" {
  for_each    = local.profiles
  name        = each.value.display_name
  description = "${each.value.description} Persistent home."
  icon        = each.value.icon
  default     = each.key == "isolated"
  parameters = {
    network_isolation = each.key
    runtime           = local.runtimes[0]
    home              = "persistent"
  }

  dynamic "prebuilds" {
    for_each = var.prebuild_instances > 0 ? [1] : []
    content {
      instances = var.prebuild_instances
    }
  }
}

# No prebuilds: the warm pools already keep booted sandboxes.
data "coder_workspace_preset" "scratch" {
  for_each    = toset(local.scratch_profiles)
  name        = "${local.profiles[each.key].display_name}, scratch home"
  description = "A booted sandbox from the warm pool. Home is deleted on stop."
  icon        = "/emojis/26a1.png"
  parameters = {
    network_isolation = each.key
    runtime           = local.runtimes[0]
    home              = "scratch"
  }
}

locals {
  name    = "coder-${data.coder_workspace.me.id}"
  scratch = data.coder_parameter.home.value == "scratch"
  # The pool name suffix of each scratch profile. Keep in line with
  # cluster/main.tf.
  pool_suffix = { isolated = "", github = "-github" }
  profile     = local.profiles[data.coder_parameter.network_isolation.value]

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

  access_host       = try(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)", data.coder_workspace.me.access_url)[0], "")
  access_host_is_ip = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", local.access_host))
  access_port = try(
    tonumber(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/:]+:([0-9]+)", data.coder_workspace.me.access_url)[0]),
    startswith(lower(data.coder_workspace.me.access_url), "http://") ? 80 : 443,
  )
  coder_port = coalesce(var.coder_egress_port, local.access_port)
  host_aliases = var.coder_host_ip != "" && !local.access_host_is_ip ? [{
    ip        = var.coder_host_ip
    hostnames = [local.access_host]
  }] : null
  # Leave hostAliases out when empty. A null value makes every plan
  # update the Sandbox.
  host_alias_field = { for k, v in { hostAliases = local.host_aliases } : k => v if v != null }

  # Copy the image's dotfiles into a new, empty home.
  seed_home = "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/. /home/coder/ 2>/dev/null || true"

  # The policy check in shared/start-agent.sh, also used by the warm pools.
  policy_check = file("${path.module}/shared/start-agent.sh")

  agent_command = join("\n", [
    local.seed_home,
    "ulimit -n 65536 2>/dev/null || true",
    var.network_policy_gate ? local.policy_check : "exec /usr/local/bin/coder agent",
  ])

  resources = local.defaults.resources
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

# Scratch home: claim a booted sandbox from the warm pool. The pooled Pod
# reads the agent token from this annotation through the downward API and
# then starts the agent. The warm pool's SandboxTemplate owns its
# NetworkPolicy.
resource "kubernetes_manifest" "claim" {
  count = local.scratch ? data.coder_workspace.me.start_count : 0

  lifecycle {
    precondition {
      condition     = contains(local.scratch_profiles, data.coder_parameter.network_isolation.value)
      error_message = "A scratch home supports only Fully isolated and GitHub only, because Pods of one warm pool share network rules on Amazon VPC CNI. Pick a persistent home for Public internet."
    }
  }

  manifest = {
    apiVersion = "extensions.agents.x-k8s.io/v1beta1"
    kind       = "SandboxClaim"
    metadata = {
      name      = local.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      warmPoolRef = { name = "coder-${data.coder_parameter.runtime.value}${lookup(local.pool_suffix, data.coder_parameter.network_isolation.value, "")}" }
      lifecycle   = { shutdownPolicy = "Delete" }
      additionalPodMetadata = {
        annotations = {
          "coder.com/agent-token"  = coder_agent.dev.token
          "coder.com/workspace-id" = data.coder_workspace.me.id
        }
      }
    }
  }
  computed_fields = ["metadata.labels", "metadata.annotations", "metadata.finalizers", "spec.lifecycle"]
}

# Persistent home: Coder owns the disk, so it outlives the Sandbox.
resource "kubernetes_persistent_volume_claim_v1" "home" {
  count = local.scratch ? 0 : 1
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

# Deny all ingress. Allow egress to Coder, plus the profile's ranges and
# DNS. The agent dials out, so no ingress is needed.
resource "kubernetes_network_policy_v1" "workspace" {
  count = local.scratch ? 0 : 1
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
      for_each = length(local.profile.cidrs) > 0 ? [1] : []
      content {
        dynamic "to" {
          for_each = local.profile.cidrs
          content {
            ip_block {
              cidr   = to.value
              except = local.profile.except
            }
          }
        }
        ports {
          protocol = "TCP"
          port     = "443"
        }
        ports {
          protocol = "TCP"
          port     = "80"
        }
      }
    }

    dynamic "egress" {
      for_each = length(local.profile.cidrs) > 0 ? [1] : []
      content {
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
}

resource "kubernetes_secret_v1" "agent_token" {
  count = local.scratch ? 0 : data.coder_workspace.me.start_count
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
resource "terraform_data" "sandbox_name" {
  count = local.scratch ? 0 : data.coder_workspace.me.start_count
}

# agent-sandbox creates the Pod. Stop deletes the Sandbox and its Pod, but
# not the home disk.
resource "kubernetes_manifest" "sandbox" {
  count = local.scratch ? 0 : data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_network_policy_v1.workspace,
  ]

  lifecycle {
    precondition {
      condition     = data.coder_parameter.network_isolation.value != "isolated" || local.access_host_is_ip || var.coder_host_ip != ""
      error_message = "Fully isolated blocks DNS, so the agent cannot resolve ${local.access_host}. Set the coder_host_ip template variable to the IP address of the Coder server."
    }
  }

  manifest = {
    apiVersion = "agents.x-k8s.io/v1beta1"
    kind       = "Sandbox"
    metadata = {
      name      = "${local.name}-${substr(terraform_data.sandbox_name[0].id, 0, 8)}-pod"
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      shutdownPolicy = "Delete"
      podTemplate = {
        metadata = {
          labels = local.labels
        }
        spec = merge({
          runtimeClassName              = data.coder_parameter.runtime.value
          automountServiceAccountToken  = false
          enableServiceLinks            = false
          terminationGracePeriodSeconds = 2
          dnsPolicy                     = "None"
          dnsConfig = {
            nameservers = local.dns_servers
          }
          securityContext = {
            runAsNonRoot        = true
            runAsUser           = 1000
            runAsGroup          = 1000
            fsGroup             = 1000
            fsGroupChangePolicy = "OnRootMismatch"
            seccompProfile = {
              type = "RuntimeDefault"
            }
          }
          containers = [{
            name            = "dev"
            image           = var.workspace_image
            imagePullPolicy = "IfNotPresent"
            command         = ["bash", "-c", local.agent_command]
            workingDir      = "/home/coder"
            env = [
              {
                name = "CODER_AGENT_TOKEN"
                valueFrom = {
                  secretKeyRef = {
                    name = kubernetes_secret_v1.agent_token[0].metadata[0].name
                    key  = "token"
                  }
                }
              },
              { name = "CODER_AGENT_URL", value = data.coder_workspace.me.access_url },
              { name = "CODER_AGENT_AUTH", value = "token" },
            ]
            securityContext = {
              allowPrivilegeEscalation = false
              runAsNonRoot             = true
              capabilities = {
                drop = ["ALL"]
              }
            }
            resources = local.resources
            volumeMounts = [
              { name = "home", mountPath = "/home/coder" },
              { name = "tmp", mountPath = "/tmp" },
            ]
          }]
          volumes = [
            {
              name = "home"
              persistentVolumeClaim = {
                claimName = kubernetes_persistent_volume_claim_v1.home[0].metadata[0].name
              }
            },
            { name = "tmp", emptyDir = {} },
          ]
        }, local.host_alias_field)
      }
    }
  }
  # The controller adds labels, annotations, and finalizers, and the API
  # server fills container defaults.
  computed_fields = [
    "metadata.labels",
    "metadata.annotations",
    "metadata.finalizers",
    "spec.podTemplate.spec.containers",
  ]
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

# A prebuild or a GitHub only warm pool clones the repository before anyone
# claims it, and the module skips the clone when the folder exists, so a
# claim does not wait for it.
module "git-clone" {
  count    = data.coder_workspace.me.start_count != 0 && var.git_repo_url != "" && data.coder_parameter.network_isolation.value != "isolated" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.dev.id
  url      = var.git_repo_url
  base_dir = "/home/coder"
}

# Claude Code is in the image, so the template only sets its environment.
# The claude-code registry module would do the same, but it reads the
# deprecated coder_task data source, which adds a warning to every build.
resource "coder_env" "claude_disable_autoupdater" {
  count    = var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}

# With the AI Gateway, Claude Code reaches Anthropic through the Coder
# server and signs in with the owner's session token.
resource "coder_env" "anthropic_base_url" {
  count    = var.enable_ai_gateway && var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

resource "coder_env" "anthropic_auth_token" {
  count    = var.enable_ai_gateway && var.enable_claude_code ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
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
