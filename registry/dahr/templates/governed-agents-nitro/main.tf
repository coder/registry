terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

# Governed AI agents on Amazon EKS.
#
# Every workspace is one Pod with these layers around it. None of them trust
# anything that runs inside the Pod, and the agent cannot change any of them.
#
#   1. Hardware isolation: AWS Nitro Sandboxes. With sandbox_runtime_class =
#      isolated-sandbox on an EKS Auto Mode cluster, each workspace Pod runs
#      in its own VM, created by the Nitro hypervisor, with its own kernel.
#   2. Admission: the operator can enforce Pod Security restricted on the namespace.
#   3. Network, layer 3 and 4: a default-deny NetworkPolicy for the Coder
#      server, this workspace's proxy, and the EKS Pod Identity Agent. The
#      operator must enable NetworkPolicy enforcement on the cluster.
#   4. Network, host names: a Squid egress proxy in its own Pod. It allows
#      only the host names of the chosen egress bundles and logs requests.
#   5. AWS egress (optional, configured outside this template): the operator
#      can route agent node traffic through AWS Network Firewall, an S3 gateway
#      endpoint, and Route 53 Resolver DNS Firewall. See node_pool.
#   6. Identity: one service account, mapped to an IAM role with EKS Pod
#      Identity. Model traffic goes through Coder AI Gateway with a scoped
#      Coder token, so no provider key enters the workspace.
#
# Patterns adapted from coder-labs/kubernetes-sandboxed in coder/registry
# (Apache-2.0): the egress proxy, the policy gate, and the scoped AI Gateway
# token.

provider "coder" {}

# --------------------------------------------------------------------------
# Template variables (set by the platform team at push time)
# --------------------------------------------------------------------------

variable "use_kubeconfig" {
  description = "Use ~/.kube/config on the provisioner. Leave false when Coder runs in the same EKS cluster."
  type        = bool
  default     = false
}

variable "kube_host" {
  description = "API server URL of the cluster that runs workspaces, when it is not the cluster Coder runs in. Supply this from your EKS cluster."
  type        = string
  default     = ""

  validation {
    condition     = var.kube_host == "" || startswith(var.kube_host, "https://")
    error_message = "kube_host must be empty or an https:// URL."
  }
}

variable "kube_ca_certificate" {
  description = "Base64 CA certificate of kube_host."
  type        = string
  default     = ""
}

variable "kube_token" {
  description = "Token of the provisioner's namespace-scoped service account in kube_host's cluster."
  type        = string
  default     = ""
  sensitive   = true
}

variable "namespace" {
  description = "Namespace for workspaces. Create it with Pod Security and the provisioner Role before using the template."
  type        = string
  default     = "coder-workspaces"
}

variable "workspace_image" {
  description = "Workspace image built and hosted by the operator. Include Coder, Bash, code-server, Claude Code, and Kiro CLI as needed. Use a fixed tag or digest, not :latest."
  type        = string

  validation {
    condition = (
      length(trimspace(var.workspace_image)) > 0 &&
      !endswith(var.workspace_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.workspace_image), length(split("/", var.workspace_image)) - 1)))
    )
    error_message = "workspace_image needs a tag other than :latest, or a digest."
  }
}

variable "proxy_image" {
  description = "Egress proxy image built and hosted by the operator. Include Squid configured to read /etc/squid-conf/squid.conf. Use a fixed tag or digest, not :latest."
  type        = string

  validation {
    condition = (
      length(trimspace(var.proxy_image)) > 0 &&
      !endswith(var.proxy_image, ":latest") &&
      can(regex("[:@]", element(split("/", var.proxy_image), length(split("/", var.proxy_image)) - 1)))
    )
    error_message = "proxy_image needs a tag other than :latest, or a digest."
  }
}

variable "coder_egress_cidrs" {
  description = "IPv4 ranges of the Coder access URL, for example the static IPs of its Network Load Balancer. Workspaces reach only these directly."
  type        = list(string)

  validation {
    condition     = length(var.coder_egress_cidrs) > 0 && alltrue([for c in var.coder_egress_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "coder_egress_cidrs needs at least one IPv4 CIDR, such as 203.0.113.10/32."
  }
}

variable "coder_egress_port" {
  description = "TCP port to reach Coder. 0 uses the port of the access URL."
  type        = number
  default     = 0
}

variable "coder_host_ip" {
  description = "IPv4 address for the access URL host name. Workspaces have no DNS, so the template writes it to /etc/hosts. Leave empty when the access URL is an IP address."
  type        = string
  default     = ""

  validation {
    condition     = var.coder_host_ip == "" || (can(cidrhost("${var.coder_host_ip}/32", 0)) && !strcontains(var.coder_host_ip, ":"))
    error_message = "coder_host_ip must be empty or an IPv4 address."
  }
}

variable "sandbox_runtime_class" {
  description = "RuntimeClass for hardware isolation. The default isolated-sandbox runs on EKS Auto Mode with Nitro Sandboxes. Other installed runtimes, such as kata-qemu or gvisor, also work. Empty uses the node default runtime."
  type        = string
  default     = "isolated-sandbox"

  validation {
    condition     = var.sandbox_runtime_class == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.sandbox_runtime_class))
    error_message = "sandbox_runtime_class must be empty or a valid RuntimeClass name."
  }
}

variable "aws_region" {
  description = "AWS Region of the EKS cluster and the artifacts bucket."
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name. Needed when the template creates a Pod Identity association for each workspace."
  type        = string
  default     = ""
}

variable "workspace_role_arn" {
  description = "IAM role for workspaces, supplied by the operator. Each workspace gets its own service account mapped to this role. Scope S3 access with the kubernetes-service-account session tag."
  type        = string
  default     = ""

  validation {
    condition     = var.workspace_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.workspace_role_arn))
    error_message = "workspace_role_arn must be empty or an IAM role ARN."
  }
}

variable "shared_service_account" {
  description = "Use one existing service account for every workspace instead of one each, as in aws eks create-pod-identity-association --service-account agent-workspace. Overrides workspace_role_arn."
  type        = string
  default     = ""
}

variable "artifacts_bucket" {
  description = "S3 bucket for agent artifacts. Scope workspace access to workspaces/<its service account>/ in its IAM role. Empty leaves S3 out."
  type        = string
  default     = ""

  validation {
    condition = var.artifacts_bucket == "" || (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifacts_bucket)) &&
      !strcontains(var.artifacts_bucket, "..") &&
      !strcontains(var.artifacts_bucket, ".-") &&
      !strcontains(var.artifacts_bucket, "-.") &&
      !can(cidrhost("${var.artifacts_bucket}/32", 0))
    )
    error_message = "artifacts_bucket must be an S3 bucket name, without shell metacharacters."
  }
}

variable "github_org" {
  description = "GitHub organization the agents work in. Used in bundle labels and by the firewall demo. Limit writes to it with GitHub organization settings and scoped credentials."
  type        = string
  default     = ""

  validation {
    condition     = var.github_org == "" || can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_org))
    error_message = "github_org must be a GitHub organization name."
  }
}

variable "git_repo_url" {
  description = "HTTPS repository to clone into /home/coder at start. Empty clones nothing."
  type        = string
  default     = ""
}

variable "extra_allowed_hosts" {
  description = "Comma-separated public host names to add to the egress proxy allowlist. With AWS Network Firewall, allow them there too. Avoid hosts that store user content."
  type        = string
  default     = ""

  validation {
    condition = var.extra_allowed_hosts == "" || alltrue([
      for raw in split(",", var.extra_allowed_hosts) :
      length(trimspace(raw)) <= 253 &&
      length(split(".", trimspace(raw))) >= 2 &&
      !can(cidrhost("${trimspace(raw)}/32", 0)) &&
      alltrue([for label in split(".", trimspace(raw)) : length(label) <= 63 && can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))])
    ])
    error_message = "extra_allowed_hosts must contain only comma-separated public host names, not IP addresses or proxy directives."
  }
}

variable "ai_gateway_token_mode" {
  description = "Coder token that Claude Code sends to AI Gateway. scoped: a new token limited to user:read_personal, which expires after ai_gateway_token_lifetime_hours but is not attributed to the workspace in AI Gateway. session: the owner's workspace session token, which AI Gateway attributes to the workspace and Coder deletes on stop, but which has full API access."
  type        = string
  default     = "scoped"

  validation {
    condition     = contains(["scoped", "session"], var.ai_gateway_token_mode)
    error_message = "ai_gateway_token_mode must be scoped or session."
  }
}

variable "ai_gateway_token_lifetime_hours" {
  description = "Lifetime of the scoped AI Gateway token. Keep it near the template's autostop time. It cannot exceed the deployment's maximum token lifetime."
  type        = number
  default     = 24
}

variable "ai_gateway_provider" {
  description = "Name of the AI Gateway provider that Claude Code uses. The route is /api/v2/ai-gateway/<name>. Use the name of your Bedrock provider to serve Claude from Amazon Bedrock."
  type        = string
  default     = "anthropic"
}

variable "enable_kiro" {
  description = "Offer the Kiro CLI bundle in the workspace-agents profile. Choosing it allows Kiro's service endpoints and adds the Kiro app. Kiro sends model traffic to its own service, not through AI Gateway."
  type        = bool
  default     = true
}

variable "kiro_region" {
  description = "Kiro service Region: us-east-1 or eu-central-1. Also the Region of the IAM Identity Center or Builder ID sign-in."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "eu-central-1"], var.kiro_region)
    error_message = "kiro_region must be us-east-1 or eu-central-1."
  }
}

variable "node_pool" {
  description = "Node label key=value of an agent node group, such as coder.com/pool=agent-egress. Workspace and proxy Pods run only there and tolerate its taint. Configure AWS Network Firewall on the node subnets separately. Empty runs on any non-Fargate node."
  type        = string
  default     = ""

  validation {
    condition     = var.node_pool == "" || can(regex("^[^=]+=[^=]+$", var.node_pool))
    error_message = "node_pool must be key=value."
  }
}

variable "prebuild_instances" {
  description = "Prebuilt workspaces per preset (Coder Premium). 0 turns them off."
  type        = number
  default     = 1
}

variable "home_disk_size" {
  description = "Home volume size in GiB. It survives stop and start."
  type        = number
  default     = 10
}

variable "storage_class_name" {
  description = "StorageClass for the home volume. Empty uses the cluster default. Prefer WaitForFirstConsumer."
  type        = string
  default     = ""
}

variable "network_policy_gate" {
  description = "Start the Coder agent only after the NetworkPolicy blocks the Kubernetes API server, and stop it if that ever changes."
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "Comma-separated IPv4 DNS servers for the egress proxy. Empty uses the VPC resolver (169.254.169.253). Custom servers can bypass Route 53 Resolver DNS Firewall. Workspaces have no DNS."
  type        = string
  default     = ""

  validation {
    condition = var.dns_servers == "" || alltrue([
      for server in split(",", var.dns_servers) :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", trimspace(server))) &&
      can(cidrhost("${trimspace(server)}/32", 0))
    ])
    error_message = "dns_servers must contain only comma-separated IPv4 addresses."
  }
}

variable "github_external_auth_id" {
  description = "ID of a GitHub external auth provider in Coder, for git credentials without tokens in the workspace. Empty skips it."
  type        = string
  default     = ""
}

provider "kubernetes" {
  config_path            = var.kube_host == "" && var.use_kubeconfig ? "~/.kube/config" : null
  host                   = var.kube_host != "" ? var.kube_host : null
  cluster_ca_certificate = var.kube_host != "" ? base64decode(var.kube_ca_certificate) : null
  token                  = var.kube_host != "" ? var.kube_token : null
}

# The provisioner uses its own AWS credentials when it creates an association.
# Skipping the STS check keeps builds fast and works when no AWS resource is
# planned. Terraform configures the provider even then, so without a
# per-workspace association it gets placeholder keys and never looks for
# real credentials. The Coder server then needs no AWS identity.
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = local.creates_aws_resources ? null : true
  access_key                  = local.creates_aws_resources ? null : "unused"
  secret_key                  = local.creates_aws_resources ? null : "unused"
}

locals {
  # Only the per-workspace Pod Identity association calls AWS.
  creates_aws_resources = var.shared_service_account == "" && var.workspace_role_arn != ""
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_external_auth" "github" {
  count    = var.github_external_auth_id != "" ? 1 : 0
  id       = var.github_external_auth_id
  optional = true
}

# --------------------------------------------------------------------------
# Profiles: who runs the agent loop and what the workspace can reach
# --------------------------------------------------------------------------

locals {
  profiles = {
    "coder-agents" = {
      display_name = "Coder Agents"
      description  = "Agent loop in Coder. Reaches Coder; selected bundles and an optional AWS identity control other access."
      icon         = "/icon/coder.svg"
      egress       = true
      claude       = false
    }
    "workspace-agents" = {
      display_name = "Claude Code and Kiro in the workspace"
      description  = "Claude Code through AI Gateway and Kiro CLI run in the workspace. Selected bundles control proxy destinations."
      icon         = "/icon/claude.svg"
      egress       = true
      claude       = true
    }
    "isolated" = {
      display_name = "Isolated"
      description  = "Coder only. No proxy, no internet, no DNS, no AWS identity."
      icon         = "/emojis/1f512.png"
      egress       = false
      claude       = false
    }
  }

  github_hosts = [
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "objects.githubusercontent.com",
  ]
  bucket_host = var.artifacts_bucket != "" && local.aws_identity ? "${var.artifacts_bucket}.s3.${var.aws_region}.amazonaws.com" : ""
  extra_hosts = compact([for h in split(",", var.extra_allowed_hosts) : lower(trimspace(h))])

  # Kiro CLI's service endpoints, from Kiro's firewall guide: inference and
  # settings, the legacy Q endpoint, token exchange, and device-flow sign-in
  # for AWS Builder ID or IAM Identity Center. Telemetry and update downloads
  # are left out on purpose, so they show up as blocked.
  kiro_hosts = [
    "runtime.${var.kiro_region}.kiro.dev",
    "management.${var.kiro_region}.kiro.dev",
    "q.${var.kiro_region}.amazonaws.com",
    "prod.us-east-1.auth.desktop.kiro.dev",
    "oidc.${var.kiro_region}.amazonaws.com",
    "app.kiro.dev",
  ]

  # Egress bundles: vetted sets of host names for the egress proxy. The
  # operator picks bundles when creating the workspace and never writes
  # rules. profiles limits where a bundle is offered. With the AWS egress
  # layer, AWS Network Firewall holds the approved names for the whole account,
  # so a bundle only works if its hosts are approved there too.
  egress_bundles = merge(
    {
      "github" = {
        label       = var.github_org != "" ? "GitHub: clone, push, and pull requests (${var.github_org})" : "GitHub: clone, push, and pull requests"
        description = "Clone over HTTPS and use the GitHub API. Which repositories the agent can write to is set by its GitHub credentials and organization settings, not by the network."
        hosts       = local.github_hosts
        profiles    = ["coder-agents", "workspace-agents"]
      }
      "npm" = {
        label       = "npm: install packages"
        description = "Download from registry.npmjs.org."
        hosts       = ["registry.npmjs.org"]
        profiles    = ["coder-agents", "workspace-agents"]
      }
      "pypi" = {
        label       = "PyPI: install packages"
        description = "Download from pypi.org."
        hosts       = ["pypi.org", "files.pythonhosted.org"]
        profiles    = ["coder-agents", "workspace-agents"]
      }
      "go" = {
        label       = "Go: download modules"
        description = "Download modules through proxy.golang.org and check them against sum.golang.org."
        hosts       = ["proxy.golang.org", "sum.golang.org"]
        profiles    = ["coder-agents", "workspace-agents"]
      }
      "unapproved-demo" = {
        label       = "Demo: example.com, subject to your upstream firewall"
        description = "Allow example.com through this workspace's proxy. An external firewall blocks it only if you configure one to deny that host."
        hosts       = ["example.com"]
        profiles    = ["coder-agents", "workspace-agents"]
      }
    },
    {
      for k, b in {
        "kiro" = {
          label       = "Kiro CLI"
          description = "Kiro's model service and sign-in. Adds the Kiro app. Kiro telemetry and self-updates stay blocked."
          hosts       = local.kiro_hosts
          profiles    = ["workspace-agents"]
        }
      } : k => b if var.enable_kiro
    },
  )
  default_egress_bundles = ["github", "kiro"]

  private_cidrs = ["10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"]
  dns_servers   = var.dns_servers != "" ? [for server in split(",", var.dns_servers) : trimspace(server)] : ["169.254.169.253"]

  # EKS Pod Identity Agent, on every node at a link-local address.
  pod_identity_agent = "169.254.170.23"

  # A Nitro Sandbox gets its vCPUs and memory from the Pod's requests
  # at boot, so a Nitro workspace requests its full size.
  nitro_sandbox      = contains(["isolated-sandbox", "confidential-sandbox"], var.sandbox_runtime_class)
  workspace_limits   = { cpu = "2", memory = "4Gi" }
  workspace_requests = local.nitro_sandbox ? local.workspace_limits : { cpu = "500m", memory = "1Gi" }
}

data "coder_parameter" "profile" {
  name         = "profile"
  display_name = "Agent profile"
  description  = "Where the agent loop runs and what the workspace can reach. Fixed after create."
  type         = "string"
  form_type    = "radio"
  default      = "coder-agents"
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

# Vetted egress bundles. Each adds host names to the egress proxy. Changing
# it later restarts the proxy with the new allowlist.
data "coder_parameter" "egress_bundles" {
  count        = local.profile.egress ? 1 : 0
  name         = "egress_bundles"
  display_name = "Allowed destinations"
  description  = "What the workspace can reach besides Coder, subject to optional upstream firewall rules and AWS identity."
  type         = "list(string)"
  form_type    = "multi-select"
  mutable      = true
  order        = 2
  default      = jsonencode([for k in local.default_egress_bundles : k if contains(keys(local.offered_bundles), k)])

  dynamic "option" {
    for_each = local.offered_bundles
    content {
      name        = option.value.label
      description = option.value.description
      value       = option.key
    }
  }
}

# One preset per profile, each with prebuilds. A preset sets every
# immutable parameter, so claiming a prebuild changes no Pod. Presets leave
# out egress_bundles, so the operator can still pick bundles. A prebuild
# starts with the defaults, and a claim with other bundles restarts the Pods
# with the new allowlists.
data "coder_workspace_preset" "profile" {
  for_each    = local.profiles
  name        = each.value.display_name
  description = each.value.description
  icon        = each.value.icon
  default     = each.key == "coder-agents"
  parameters  = { profile = each.key }

  dynamic "prebuilds" {
    for_each = var.prebuild_instances > 0 ? [1] : []
    content {
      instances = var.prebuild_instances
    }
  }
}

locals {
  profile_key = data.coder_parameter.profile.value
  profile     = local.profiles[local.profile_key]

  # Bundles offered for this profile, and the ones chosen. A value that is
  # not offered, for example from the API, is ignored.
  offered_bundles = { for k, b in local.egress_bundles : k => b if contains(b.profiles, local.profile_key) }
  chosen_bundle_keys = local.profile.egress ? [
    for k in try(jsondecode(data.coder_parameter.egress_bundles[0].value), []) : k if contains(keys(local.offered_bundles), k)
  ] : []
  chosen_bundles = [for k in local.chosen_bundle_keys : local.offered_bundles[k]]

  kiro        = local.profile.claude && contains(local.chosen_bundle_keys, "kiro")
  proxy_hosts = local.profile.egress ? distinct(compact(concat(flatten([for b in local.chosen_bundles : b.hosts]), [local.bucket_host], local.extra_hosts))) : []
  proxy       = length(local.proxy_hosts) > 0

  identity_mode = var.shared_service_account != "" ? "shared" : (var.workspace_role_arn != "" ? "per-workspace" : "none")
  aws_identity  = local.profile.egress && local.identity_mode != "none"

  claude = local.profile.claude

  # A dedicated agent node group. Set up firewall routing separately.
  node_pool_key   = var.node_pool != "" ? split("=", var.node_pool)[0] : ""
  node_pool_value = var.node_pool != "" ? split("=", var.node_pool)[1] : ""

  # Names use the workspace ID, never the owner or workspace name, so a
  # prebuild claim does not replace anything.
  name    = "coder-${data.coder_workspace.me.id}"
  sa_name = local.identity_mode == "shared" ? var.shared_service_account : "${local.name}-agent"

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

  access_url        = trimsuffix(data.coder_workspace.me.access_url, "/")
  access_host       = try(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)", local.access_url)[0], "")
  access_host_is_ip = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", local.access_host))
  access_port = try(
    tonumber(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/:]+:([0-9]+)", local.access_url)[0]),
    startswith(lower(local.access_url), "http://") ? 80 : 443,
  )
  coder_port = var.coder_egress_port > 0 ? var.coder_egress_port : local.access_port

  squid_conf = templatefile("${path.module}/squid.conf.tftpl", {
    allowed_domains = join(" ", local.proxy_hosts)
    dns_servers     = join(" ", local.dns_servers)
  })

  agent_command = join("\n", [
    "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/. /home/coder/ 2>/dev/null || true",
    "ulimit -n 65536 2>/dev/null || true",
    var.network_policy_gate ? file("${path.module}/start-agent.sh") : "exec /usr/local/bin/coder agent",
  ])
}

# --------------------------------------------------------------------------
# Coder agent
# --------------------------------------------------------------------------

resource "coder_agent" "dev" {
  os   = "linux"
  arch = "amd64"

  metadata {
    display_name = "Isolation"
    key          = "0_isolation"
    script       = "echo \"$SANDBOX_RUNTIME, kernel $(uname -r)\""
    interval     = 600
    timeout      = 1
  }
  metadata {
    display_name = "Network policy"
    key          = "1_network_policy"
    script       = "curl -sk --noproxy '*' --connect-timeout 1 -m 2 -o /dev/null \"https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/\" && echo 'NOT ENFORCED' || echo 'enforced'"
    interval     = 30
    timeout      = 3
  }
  metadata {
    display_name = "AWS identity"
    key          = "2_aws_identity"
    script       = "[ -n \"$AWS_CONTAINER_CREDENTIALS_FULL_URI\" ] && echo \"Pod Identity, no static keys\" || echo none"
    interval     = 600
    timeout      = 1
  }
  metadata {
    display_name = "CPU"
    key          = "3_cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory"
    key          = "4_mem"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

# --------------------------------------------------------------------------
# Identity: one service account per workspace, mapped by EKS Pod Identity
# --------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "agent" {
  count = local.aws_identity && local.identity_mode == "per-workspace" ? 1 : 0

  metadata {
    name        = local.sa_name
    namespace   = var.namespace
    labels      = local.labels
    annotations = local.owner_annotations
  }
  automount_service_account_token = false
}

resource "aws_eks_pod_identity_association" "agent" {
  count = length(kubernetes_service_account_v1.agent)

  cluster_name    = var.eks_cluster_name
  namespace       = var.namespace
  service_account = kubernetes_service_account_v1.agent[0].metadata[0].name
  role_arn        = var.workspace_role_arn

  tags = {
    "coder.workspace.id" = data.coder_workspace.me.id
  }

  lifecycle {
    precondition {
      condition     = var.eks_cluster_name != ""
      error_message = "Set eks_cluster_name so the template can create the Pod Identity association."
    }
  }
}

# Associations are eventually consistent. The Pod must be created after the
# association is in place, or EKS does not inject credentials. Only the
# first build of a workspace waits. Prebuilds pay this cost ahead of time.
resource "time_sleep" "pod_identity" {
  count           = length(aws_eks_pod_identity_association.agent)
  create_duration = "15s"
  triggers = {
    association = aws_eks_pod_identity_association.agent[0].association_id
  }
}

# VPC CNI tracks a Pod by its name without the last "-" part. For a
# Deployment that is <deployment>-<pod template hash>, which is the same on
# every start because the template does not change. If a new Pod shares it
# with an old one, deleting the old Pod removes the new Pod's eBPF rules and
# the new Pod stays open ("no bpf context registered" in the node agent
# log). This ID exists only while the workspace runs, so each start from
# stopped gets a new pod template hash. Claiming a prebuild keeps it, so the
# Pod is not replaced.
resource "random_id" "pod_generation" {
  count       = data.coder_workspace.me.start_count
  byte_length = 4
}

locals {
  pod_annotations = {
    "coder.com/pod-generation" = try(random_id.pod_generation[0].hex, "")
  }

  # Fargate enforces no NetworkPolicy and supports no Pod Identity, so
  # workspaces and proxies must never land there.
  not_fargate = {
    key      = "eks.amazonaws.com/compute-type"
    operator = "NotIn"
    values   = ["fargate"]
  }
}

# --------------------------------------------------------------------------
# Storage
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Network layer 1: default-deny NetworkPolicy, enforced by the VPC CNI
# --------------------------------------------------------------------------

# No ingress at all. The Coder agent dials out, so the web terminal, IDEs,
# and Coder Agents tools all relay through the Coder server.
# Egress: Coder, the Pod's own proxy, and the Pod Identity Agent. No DNS.
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

    dynamic "egress" {
      for_each = local.aws_identity ? [1] : []
      content {
        to {
          ip_block {
            cidr = "${local.pod_identity_agent}/32"
          }
        }
        ports {
          protocol = "TCP"
          port     = "80"
        }
      }
    }
  }
}

# The proxy accepts only its own workspace and reaches only public
# addresses on 443, plus DNS. Squid also refuses private addresses itself.
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
      ports {
        protocol = "TCP"
        port     = "443"
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

# --------------------------------------------------------------------------
# Network layer 2: host name allowlist in a separate proxy Pod
# --------------------------------------------------------------------------

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

# The workspace has no DNS, so it reaches the proxy by cluster IP. The IP
# stays the same for the life of the workspace.
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

resource "kubernetes_deployment_v1" "proxy" {
  count            = local.proxy ? data.coder_workspace.me.start_count : 0
  depends_on       = [kubernetes_network_policy_v1.proxy]
  wait_for_rollout = false

  metadata {
    name      = "${local.name}-proxy"
    namespace = var.namespace
    labels    = local.proxy_labels
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = local.proxy_labels
    }
    template {
      metadata {
        labels = local.proxy_labels
        annotations = merge(local.pod_annotations, {
          # Squid reads its config only at start. A new config rolls the Pod.
          "checksum/squid-conf" = sha256(local.squid_conf)
        })
      }
      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = local.not_fargate.key
                  operator = local.not_fargate.operator
                  values   = local.not_fargate.values
                }
                dynamic "match_expressions" {
                  for_each = var.node_pool != "" ? [1] : []
                  content {
                    key      = local.node_pool_key
                    operator = "In"
                    values   = [local.node_pool_value]
                  }
                }
              }
            }
          }
        }
        dynamic "toleration" {
          for_each = var.node_pool != "" ? [1] : []
          content {
            key      = local.node_pool_key
            operator = "Equal"
            value    = local.node_pool_value
            effect   = "NoSchedule"
          }
        }
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
            # The provider sends false when this is unset, which Pod Security
            # restricted rejects even though the Pod level sets true.
            run_as_non_root            = true
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
  }
}

# --------------------------------------------------------------------------
# Firewall demo script, read-only to the workspace
# --------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "demo" {
  count = local.profile.egress ? 1 : 0

  metadata {
    name      = "${local.name}-demo"
    namespace = var.namespace
    labels    = local.labels
  }
  data = {
    "firewall-demo.sh" = templatefile("${path.module}/firewall-demo.sh.tftpl", {
      github_org        = var.github_org
      bucket            = local.aws_identity ? var.artifacts_bucket : ""
      kiro_runtime_host = local.profile.claude && var.enable_kiro ? local.kiro_hosts[0] : ""
    })
  }
}

# --------------------------------------------------------------------------
# Workspace Pod
# --------------------------------------------------------------------------

# Only while started. The Pod reads the agent token from it, so the token is
# not in the Pod spec.
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

locals {
  proxy_url = local.proxy ? "http://${kubernetes_service_v1.proxy[0].spec[0].cluster_ip}:3128" : ""
  no_proxy  = join(",", compact(["localhost", "127.0.0.1", "::1", local.access_host, local.aws_identity ? local.pod_identity_agent : ""]))

  pod_env = merge(
    {
      SANDBOX_RUNTIME   = var.sandbox_runtime_class != "" ? var.sandbox_runtime_class : "node default runtime"
      WORKSPACE_PROFILE = local.profile_key
    },
    # curl reads only the lowercase names. Go and most other tools read the
    # uppercase ones. AWS asks for the Pod Identity Agent in NO_PROXY.
    local.proxy ? {
      HTTP_PROXY  = local.proxy_url
      HTTPS_PROXY = local.proxy_url
      http_proxy  = local.proxy_url
      https_proxy = local.proxy_url
      NO_PROXY    = local.no_proxy
      no_proxy    = local.no_proxy
    } : {},
    local.aws_identity ? {
      AWS_REGION                 = var.aws_region
      AWS_DEFAULT_REGION         = var.aws_region
      AWS_STS_REGIONAL_ENDPOINTS = "regional"
    } : {},
    local.aws_identity && var.artifacts_bucket != "" ? {
      ARTIFACTS_URI = "s3://${var.artifacts_bucket}/workspaces/${local.sa_name}/"
    } : {},
  )
}

# A Deployment, not a bare Pod: the VPC CNI enforces NetworkPolicy reliably
# only for Pods with an owner reference.
resource "kubernetes_deployment_v1" "workspace" {
  count            = data.coder_workspace.me.start_count
  depends_on       = [kubernetes_network_policy_v1.workspace, time_sleep.pod_identity]
  wait_for_rollout = false

  lifecycle {
    precondition {
      condition     = local.access_host_is_ip || var.coder_host_ip != ""
      error_message = "Workspaces have no DNS, so set coder_host_ip to the IP address of ${local.access_host}."
    }
  }

  metadata {
    name        = local.name
    namespace   = var.namespace
    labels      = local.workspace_labels
    annotations = local.owner_annotations
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = local.workspace_labels
    }

    template {
      metadata {
        labels      = local.workspace_labels
        annotations = local.pod_annotations
      }

      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = local.not_fargate.key
                  operator = local.not_fargate.operator
                  values   = local.not_fargate.values
                }
                dynamic "match_expressions" {
                  for_each = var.node_pool != "" ? [1] : []
                  content {
                    key      = local.node_pool_key
                    operator = "In"
                    values   = [local.node_pool_value]
                  }
                }
              }
            }
          }
        }
        dynamic "toleration" {
          for_each = var.node_pool != "" ? [1] : []
          content {
            key      = local.node_pool_key
            operator = "Equal"
            value    = local.node_pool_value
            effect   = "NoSchedule"
          }
        }
        # Identity and kernel isolation.
        service_account_name             = local.aws_identity ? local.sa_name : null
        runtime_class_name               = var.sandbox_runtime_class != "" ? var.sandbox_runtime_class : null
        automount_service_account_token  = false
        enable_service_links             = false
        termination_grace_period_seconds = 5

        # No DNS. Lookups go to a closed local port and fail at once. The
        # proxy resolves names, so DNS cannot carry data out.
        dns_policy = "None"
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
            value = local.access_url
          }
          env {
            name  = "CODER_AGENT_AUTH"
            value = "token"
          }
          dynamic "env" {
            for_each = local.pod_env
            content {
              name  = env.key
              value = env.value
            }
          }

          # No capabilities and no way to gain any.
          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = local.workspace_requests
            limits   = local.workspace_limits
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/coder"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
          dynamic "volume_mount" {
            for_each = local.profile.egress ? [1] : []
            content {
              name       = "demo"
              mount_path = "/etc/governed-agents"
              read_only  = true
            }
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
        dynamic "volume" {
          for_each = local.profile.egress ? [1] : []
          content {
            name = "demo"
            config_map {
              name         = kubernetes_config_map_v1.demo[0].metadata[0].name
              default_mode = "0555"
            }
          }
        }
      }
    }
  }
}

# Shown on the workspace page, so the controls are visible during a demo.
# Attached to the token Secret because Coder attaches the agent there (the
# closest resource to coder_agent.dev in the graph), and the page shows the
# metadata of the resource whose agent it displays.
resource "coder_metadata" "workspace" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_secret_v1.agent_token[0].id

  item {
    key   = "runtime class"
    value = var.sandbox_runtime_class != "" ? var.sandbox_runtime_class : "node default"
  }
  item {
    key   = "service account"
    value = local.aws_identity ? local.sa_name : "none"
  }
  item {
    key   = "IAM role"
    value = local.aws_identity && local.identity_mode == "per-workspace" ? var.workspace_role_arn : (local.identity_mode == "shared" && local.aws_identity ? "shared association" : "none")
  }
  item {
    key   = "egress bundles"
    value = length(local.chosen_bundles) > 0 ? join(", ", [for b in local.chosen_bundles : b.label]) : "none"
  }
  item {
    key   = "egress allowlist"
    value = local.proxy ? join(", ", local.proxy_hosts) : "Coder only"
  }
  item {
    key   = "AWS egress"
    value = var.node_pool != "" ? "node pool ${var.node_pool} (configure firewall routing separately)" : "none configured by this template"
  }
}

# --------------------------------------------------------------------------
# Tools
# --------------------------------------------------------------------------

module "code-server" {
  count          = local.claude ? data.coder_workspace.me.start_count : 0
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "1.6.0"
  agent_id       = coder_agent.dev.id
  folder         = "/home/coder"
  offline        = true
  install_prefix = "/opt/code-server"
  order          = 1
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count != 0 && var.git_repo_url != "" && local.profile.egress ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.dev.id
  url      = var.git_repo_url
  base_dir = "/home/coder"
}

# --------------------------------------------------------------------------
# Models: Claude Code through AI Gateway, with no provider key
# --------------------------------------------------------------------------

# The owner's session token has full Coder API access. This template uses
# it once at build time to mint a token with only the user:read_personal
# scope, which AI Gateway accepts. timestamp() defers the request to apply,
# so a plan creates nothing, and a prebuild gets its token when it is claimed.
locals {
  ai_gateway_token_ready = (
    local.claude &&
    data.coder_workspace.me.start_count > 0 &&
    !data.coder_workspace.me.is_prebuild &&
    data.coder_workspace_owner.me.session_token != ""
  )
  mint_ai_gateway_token = local.ai_gateway_token_ready && var.ai_gateway_token_mode == "scoped"
}

data "http" "ai_gateway_token" {
  count  = local.mint_ai_gateway_token ? 1 : 0
  url    = "${local.access_url}/api/v2/users/me/keys/tokens"
  method = "POST"
  request_headers = {
    "Coder-Session-Token" = data.coder_workspace_owner.me.session_token
    "Content-Type"        = "application/json"
  }
  request_body = jsonencode({
    token_name = "ai-gateway-${substr(data.coder_workspace.me.id, 0, 8)}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
    scopes     = ["user:read_personal"]
    # time.Duration in nanoseconds.
    lifetime = var.ai_gateway_token_lifetime_hours * 3600 * 1000000000
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 201
      error_message = "Could not create the AI Gateway token: HTTP ${self.status_code}."
    }
  }
}

resource "coder_env" "anthropic_base_url" {
  count    = local.claude ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${local.access_url}/api/v2/ai-gateway/${var.ai_gateway_provider}"
}

resource "coder_env" "anthropic_auth_token" {
  count    = local.ai_gateway_token_ready ? 1 : 0
  agent_id = coder_agent.dev.id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value = sensitive(
    local.mint_ai_gateway_token
    ? jsondecode(data.http.ai_gateway_token[0].response_body).key
    : data.coder_workspace_owner.me.session_token
  )
}

# Claude Code is in the image. Turn off update checks and telemetry, which
# the allowlist would block anyway, so deny logs show only real attempts.
resource "coder_env" "claude_quiet" {
  for_each = local.claude && data.coder_workspace.me.start_count > 0 ? {
    DISABLE_AUTOUPDATER                      = "1"
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
  } : {}
  agent_id = coder_agent.dev.id
  name     = each.key
  value    = each.value
}

resource "coder_app" "claude" {
  count        = local.claude ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.dev.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  order        = 2
  command      = <<-EOT
    cd /home/coder || exit 1
    exec tmux new-session -A -s claude "${local.claude_run}"
  EOT
}

locals {
  # Continue the last conversation in /home/coder, or start a new one.
  claude_run = "/opt/claude/bin/claude --continue || /opt/claude/bin/claude"
  # Sign in once with the device flow (Builder ID or IAM Identity Center),
  # then chat. The sign-in persists in the home volume.
  kiro_run = "kiro-cli whoami >/dev/null 2>&1 || kiro-cli login --use-device-flow; kiro-cli chat"
}

resource "coder_app" "kiro" {
  count        = local.kiro ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.dev.id
  slug         = "kiro"
  display_name = "Kiro"
  icon         = "/icon/kiro.svg"
  order        = 3
  command      = <<-EOT
    cd /home/coder || exit 1
    exec tmux new-session -A -s kiro "${local.kiro_run}"
  EOT
}

# Runs sample requests so the operator can inspect the results and logs.
resource "coder_app" "firewall_demo" {
  count        = local.profile.egress ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.dev.id
  slug         = "firewall-demo"
  display_name = "Firewall demo"
  icon         = "/emojis/1f6e1-fe0f.png"
  order        = 5
  command      = "bash -c '/etc/governed-agents/firewall-demo.sh; echo; read -r -p \"Press Enter to close.\" _'"
}
