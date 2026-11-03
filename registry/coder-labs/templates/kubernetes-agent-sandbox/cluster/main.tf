# Cluster setup for the kubernetes-agent-sandbox template. A cluster
# administrator applies this once. See README.md in this directory.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

variable "kubeconfig_path" {
  description = "The kubeconfig file to use."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "The kubeconfig context to use. Empty uses the current context."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "The namespace for workspaces. Use the same value in the template."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}

variable "create_namespace" {
  description = "Create the namespace. Set false if it exists already. Changing this from true to false deletes the namespace."
  type        = bool
  default     = true
}

variable "provisioner_service_account" {
  description = "The ServiceAccount of the Coder provisioner. The Coder Helm chart uses coder in the coder namespace."
  type = object({
    name      = string
    namespace = string
  })
  default = {
    name      = "coder"
    namespace = "coder"
  }
}

variable "grant_crd_read" {
  description = "Let the provisioner read CustomResourceDefinitions, which kubernetes_manifest needs at plan time. CRDs are cluster-scoped, so this adds a ClusterRole."
  type        = bool
  default     = true
}

variable "workspace_image" {
  description = "The image built from build/Dockerfile, with a fixed tag or a digest. Use the same value in the template."
  type        = string

  validation {
    condition     = !endswith(var.workspace_image, ":latest") && can(regex("(:[^/]+|@sha256:[0-9a-f]{64})$", var.workspace_image))
    error_message = "workspace_image must have a fixed tag other than :latest, or a digest."
  }
}

variable "coder_access_url" {
  description = "The Coder access URL, for example https://coder.example.com. Optional: the agent URL comes from each workspace. Set it to derive coder_egress_port, or with coder_host_ip for an access URL that uses a host name."
  type        = string
  default     = ""

  validation {
    condition     = var.coder_access_url == "" || can(regex("^https?://[^/:]+(:[0-9]+)?/?$", var.coder_access_url))
    error_message = "coder_access_url must be an http or https URL with no path, for example https://coder.example.com."
  }
}

variable "coder_egress_cidrs" {
  description = "The IPv4 CIDR ranges of the Coder server. Use the same value in the template."
  type        = list(string)

  validation {
    condition     = length(var.coder_egress_cidrs) > 0 && alltrue([for c in var.coder_egress_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "coder_egress_cidrs must have at least one valid IPv4 CIDR range, such as 203.0.113.10/32."
  }
}

variable "coder_egress_port" {
  description = "The TCP port that workspaces use to reach the Coder server. Empty uses the port of coder_access_url, or 443 if that is empty too."
  type        = number
  default     = null

  validation {
    condition     = var.coder_egress_port == null ? true : (var.coder_egress_port >= 1 && var.coder_egress_port <= 65535 && floor(var.coder_egress_port) == var.coder_egress_port)
    error_message = "coder_egress_port must be empty or a whole number from 1 to 65535."
  }
}

variable "coder_host_ip" {
  description = "The IPv4 address of the Coder server. Fully isolated blocks DNS, so if coder_access_url uses a host name, the pools map it to this address. Use the same value in the template."
  type        = string
  default     = ""

  validation {
    condition     = var.coder_host_ip == "" || (can(cidrhost("${var.coder_host_ip}/32", 0)) && !strcontains(var.coder_host_ip, ":"))
    error_message = "coder_host_ip must be empty or an IPv4 address."
  }
}

variable "runtimes" {
  description = "The RuntimeClasses to create warm pools for: gvisor, kata-qemu, kata-clh. Use the same value in the template."
  type        = list(string)
  default     = ["gvisor"]

  validation {
    condition     = length(var.runtimes) > 0 && length(var.runtimes) == length(distinct(var.runtimes)) && alltrue([for r in var.runtimes : contains(["gvisor", "kata-qemu", "kata-clh"], r)])
    error_message = "runtimes must list one or more of gvisor, kata-qemu, and kata-clh, each once."
  }
}

variable "scratch_profiles" {
  description = "The network profiles to create warm pools for: isolated, github, or both. Use the same value in the template. Empty creates no pools."
  type        = list(string)
  default     = ["isolated", "github"]

  validation {
    condition     = length(var.scratch_profiles) == length(distinct(var.scratch_profiles)) && alltrue([for p in var.scratch_profiles : contains(["isolated", "github"], p)])
    error_message = "scratch_profiles can list only isolated and github, each once."
  }
}

variable "warm_pool_replicas" {
  description = "The number of idle sandboxes in each warm pool."
  type        = number
  default     = 1

  validation {
    condition     = var.warm_pool_replicas >= 0 && floor(var.warm_pool_replicas) == var.warm_pool_replicas
    error_message = "warm_pool_replicas must be a whole number, 0 or more."
  }
}

variable "git_repo_url" {
  description = "A public Git repository that GitHub only pools clone while they wait. Use the same value in the template. Empty clones nothing."
  type        = string
  default     = ""

  validation {
    condition     = var.git_repo_url == "" || can(regex("^https://", var.git_repo_url))
    error_message = "git_repo_url must be empty or an https URL."
  }
}

variable "network_policy_gate" {
  description = "Start the Coder agent only after the NetworkPolicy blocks the Kubernetes API server. Use the same value in the template."
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "The DNS servers that workspaces use. Empty uses 8.8.8.8 and 1.1.1.1 from shared/defaults.json. Use the same value in the template."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.dns_servers : can(cidrhost("${d}/32", 0)) && !strcontains(d, ":")])
    error_message = "dns_servers must be IPv4 addresses."
  }
}

variable "enable_guardrail" {
  description = "Create the cluster-wide ClusterNetworkPolicy guardrail. Needs Amazon EKS with VPC CNI v1.21.1 or later."
  type        = bool
  default     = false
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context == "" ? null : var.kubeconfig_context
}

locals {
  defaults    = jsondecode(file("${path.module}/../shared/defaults.json"))
  dns_servers = length(var.dns_servers) > 0 ? var.dns_servers : local.defaults.dns_servers

  access_host       = try(regex("^https?://([^/:]+)", var.coder_access_url)[0], "")
  access_host_is_ip = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", local.access_host))
  access_port = var.coder_access_url == "" ? 443 : try(
    tonumber(regex("^https?://[^/:]+:([0-9]+)", var.coder_access_url)[0]),
    startswith(var.coder_access_url, "http://") ? 80 : 443,
  )
  coder_port   = coalesce(var.coder_egress_port, local.access_port)
  host_aliases = var.coder_host_ip != "" && local.access_host != "" && !local.access_host_is_ip ? [{ ip = var.coder_host_ip, hostnames = [local.access_host] }] : null
  # Leave hostAliases out when empty. A null value makes every plan
  # update the SandboxTemplate.
  host_alias_field = { for k, v in { hostAliases = local.host_aliases } : k => v if v != null }

  namespace = var.create_namespace ? kubernetes_namespace_v1.workspaces[0].metadata[0].name : var.namespace

  # One pool for each runtime and scratch profile. Keep the names in line
  # with local.pool_suffix in ../main.tf.
  pool_suffix = { isolated = "", github = "-github" }
  pools = {
    for pair in setproduct(var.runtimes, var.scratch_profiles) :
    "coder-${pair[0]}${local.pool_suffix[pair[1]]}" => {
      runtime = pair[0]
      profile = pair[1]
    }
  }

  coder_egress = {
    to    = [for c in var.coder_egress_cidrs : { ipBlock = { cidr = c } }]
    ports = [{ protocol = "TCP", port = local.coder_port }]
  }
  github_egress = [
    {
      to    = [for c in local.defaults.github_cidrs : { ipBlock = { cidr = c } }]
      ports = [{ protocol = "TCP", port = 443 }, { protocol = "TCP", port = 80 }]
    },
    {
      to    = [for d in local.dns_servers : { ipBlock = { cidr = "${d}/32" } }]
      ports = [{ protocol = "UDP", port = 53 }, { protocol = "TCP", port = 53 }]
    },
  ]

  # A pooled Pod seeds its home, clones the repository if it has one, and
  # then waits for the claim's token and the workspace's access URL. The
  # values come from env and files, not from the script text.
  pool_command = join("\n", [
    "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/. /home/coder/ 2>/dev/null || true",
    "if [ -n \"$GIT_REPO_URL\" ]; then",
    "  dir=\"/home/coder/$(basename \"$GIT_REPO_URL\" .git)\"",
    "  if [ ! -d \"$dir/.git\" ]; then",
    "    n=0",
    "    until git clone --quiet \"$GIT_REPO_URL\" \"$dir.clone\"; do",
    "      rm -rf \"$dir.clone\"",
    "      n=$((n + 1))",
    "      if [ \"$n\" -ge 5 ]; then echo \"git clone of $GIT_REPO_URL failed 5 times\" >&2; exit 1; fi",
    "      sleep 5",
    "    done",
    "    mv \"$dir.clone\" \"$dir\"",
    "  fi",
    "fi",
    "touch /tmp/.pool-ready",
    "while [ ! -s /podinfo/token ] || [ ! -s /podinfo/url ]; do sleep 0.25; done",
    "CODER_AGENT_TOKEN=\"$(cat /podinfo/token)\"",
    "CODER_AGENT_URL=\"$(cat /podinfo/url)\"",
    "export CODER_AGENT_TOKEN CODER_AGENT_URL",
    "ulimit -n 65536 2>/dev/null || true",
    var.network_policy_gate ? file("${path.module}/../shared/start-agent.sh") : "exec /usr/local/bin/coder agent",
  ])
}

resource "kubernetes_namespace_v1" "workspaces" {
  count = var.create_namespace ? 1 : 0
  metadata {
    name = var.namespace
  }
}

# The provisioner manages workspaces in this namespace only. It reads the
# SandboxTemplates and warm pools, but cannot change them.
resource "kubernetes_role_v1" "provisioner" {
  metadata {
    name      = "coder-agent-sandbox"
    namespace = local.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "secrets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["agents.x-k8s.io"]
    resources  = ["sandboxes"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["extensions.agents.x-k8s.io"]
    resources  = ["sandboxclaims"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  # Read-only, to debug workspaces with kubectl as the provisioner.
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["extensions.agents.x-k8s.io"]
    resources  = ["sandboxtemplates", "sandboxwarmpools"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "provisioner" {
  metadata {
    name      = "coder-agent-sandbox"
    namespace = local.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.provisioner.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.provisioner_service_account.name
    namespace = var.provisioner_service_account.namespace
  }
}

resource "kubernetes_cluster_role_v1" "crd_read" {
  count = var.grant_crd_read ? 1 : 0
  metadata {
    name = "coder-crd-read"
  }
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "crd_read" {
  count = var.grant_crd_read ? 1 : 0
  metadata {
    name = "coder-crd-read"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.crd_read[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.provisioner_service_account.name
    namespace = var.provisioner_service_account.namespace
  }
}

resource "kubernetes_manifest" "sandbox_template" {
  for_each = local.pools

  lifecycle {
    precondition {
      condition     = var.coder_host_ip == "" || local.access_host != ""
      error_message = "coder_host_ip needs coder_access_url, so the pools know which host name to map to it."
    }
  }

  # This configuration owns these objects, so it takes over fields that an
  # earlier kubectl apply set.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "extensions.agents.x-k8s.io/v1beta1"
    kind       = "SandboxTemplate"
    metadata = {
      name      = each.key
      namespace = local.namespace
    }
    spec = {
      networkPolicyManagement = "Managed"
      networkPolicy = {
        ingress = []
        egress  = concat([local.coder_egress], each.value.profile == "github" ? local.github_egress : [])
      }
      podTemplate = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"    = "coder-workspace"
            "app.kubernetes.io/part-of" = "coder"
          }
        }
        spec = merge({
          runtimeClassName              = each.value.runtime
          automountServiceAccountToken  = false
          enableServiceLinks            = false
          terminationGracePeriodSeconds = 2
          dnsPolicy                     = "None"
          dnsConfig                     = { nameservers = local.dns_servers }
          securityContext = {
            runAsNonRoot        = true
            runAsUser           = 1000
            runAsGroup          = 1000
            fsGroup             = 1000
            fsGroupChangePolicy = "OnRootMismatch"
            seccompProfile      = { type = "RuntimeDefault" }
          }
          containers = [{
            name            = "dev"
            image           = var.workspace_image
            imagePullPolicy = "IfNotPresent"
            workingDir      = "/home/coder"
            command         = ["bash", "-c", local.pool_command]
            env = concat(
              [
                { name = "CODER_AGENT_AUTH", value = "token" },
              ],
              each.value.profile == "github" && var.git_repo_url != "" ? [{ name = "GIT_REPO_URL", value = var.git_repo_url }] : [],
            )
            securityContext = {
              allowPrivilegeEscalation = false
              runAsNonRoot             = true
              capabilities             = { drop = ["ALL"] }
            }
            resources = local.defaults.resources
            # Ready once the home is seeded and the repository is cloned.
            readinessProbe = {
              exec          = { command = ["test", "-e", "/tmp/.pool-ready"] }
              periodSeconds = 2
            }
            volumeMounts = [
              { name = "home", mountPath = "/home/coder" },
              { name = "tmp", mountPath = "/tmp" },
              { name = "podinfo", mountPath = "/podinfo", readOnly = true },
            ]
          }]
          volumes = [
            { name = "home", emptyDir = {} },
            { name = "tmp", emptyDir = {} },
            {
              name = "podinfo"
              downwardAPI = {
                items = [
                  {
                    path     = "token"
                    fieldRef = { fieldPath = "metadata.annotations['coder.com/agent-token']" }
                  },
                  {
                    path     = "url"
                    fieldRef = { fieldPath = "metadata.annotations['coder.com/agent-url']" }
                  },
                ]
              }
            },
          ]
        }, local.host_alias_field)
      }
    }
  }
}

# Recreate replaces idle sandboxes when the SandboxTemplate changes. The
# default, OnReplenish, keeps old idle sandboxes until someone claims them.
resource "kubernetes_manifest" "warm_pool" {
  for_each   = local.pools
  depends_on = [kubernetes_manifest.sandbox_template]

  # This configuration owns these objects, so it takes over fields that an
  # earlier kubectl apply set.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "extensions.agents.x-k8s.io/v1beta1"
    kind       = "SandboxWarmPool"
    metadata = {
      name      = each.key
      namespace = local.namespace
    }
    spec = {
      replicas           = var.warm_pool_replicas
      updateStrategy     = { type = "Recreate" }
      sandboxTemplateRef = { name = each.key }
    }
  }
}

# Admin tier: checked before every NetworkPolicy, so nothing in the
# namespace can undo it. Allows Coder, blocks private ranges and ingress
# from other Pods, and passes the rest to the NetworkPolicies.
resource "kubernetes_manifest" "guardrail" {
  count = var.enable_guardrail ? 1 : 0

  # This configuration owns these objects, so it takes over fields that an
  # earlier kubectl apply set.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "networking.k8s.aws/v1alpha1"
    kind       = "ClusterNetworkPolicy"
    metadata = {
      name = "${local.namespace}-guardrail"
    }
    spec = {
      tier     = "Admin"
      priority = 100
      subject = {
        namespaces = { matchLabels = { "kubernetes.io/metadata.name" = local.namespace } }
      }
      egress = [
        {
          name   = "allow-coder"
          action = "Accept"
          to     = [{ networks = var.coder_egress_cidrs }]
          ports  = [{ portNumber = { protocol = "TCP", port = local.coder_port } }]
        },
        {
          name   = "deny-private-ranges"
          action = "Deny"
          to     = [{ networks = local.defaults.private_cidrs }]
        },
      ]
      ingress = [
        {
          name   = "deny-pods"
          action = "Deny"
          from   = [{ namespaces = {} }]
        },
      ]
    }
  }
}

# A variables file for `coder templates push --variables-file`, so the
# template uses the same values. Coder reads every value as a string, and
# the template takes runtimes and scratch_profiles comma-separated.
output "coder_variables" {
  description = "The template variables for this setup, as YAML."
  value = yamlencode({
    namespace           = local.namespace
    workspace_image     = var.workspace_image
    coder_egress_cidrs  = jsonencode(var.coder_egress_cidrs)
    coder_egress_port   = tostring(local.coder_port)
    coder_host_ip       = var.coder_host_ip
    runtimes            = join(",", var.runtimes)
    scratch_profiles    = join(",", var.scratch_profiles)
    git_repo_url        = var.git_repo_url
    network_policy_gate = tostring(var.network_policy_gate)
    dns_servers         = join(",", local.dns_servers)
  })
}
