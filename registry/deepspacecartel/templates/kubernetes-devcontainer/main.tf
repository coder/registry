# A Coder Workspace Template for Kubernetes, adapted from the official
# https://registry.coder.com/templates/coder/kubernetes template. The one
# real change from that upstream template: instead of a fixed/parameterized
# `image` variable, a workspace-level `coder_parameter` asks for a git
# repository (the one thing a stranger actually wants to type in), and a
# `devcontainerbuilder_build` resource (from
# https://github.com/DeepSpaceCartel/terraform-provider-devcontainer-builder)
# turns it into a real, pushed image before the Deployment ever starts -
# see https://deepspacecartel.github.io/devcontainer-builder/guides/coder-workspace-template/ for the full walkthrough and
# the platform prerequisites this template itself does NOT set up (a
# running devcontainer-builder instance, BuildKit).
#
# Persistence: one PVC per workspace (coder-<id>-data), mounted twice via
# subPaths - `home/` at the remote user's home and `workspaces/` at
# /workspaces - so both survive a pod restart. A `seed-home` init container
# copies the image's own home into the PVC on first start, so the mount
# doesn't hide the image's dotfiles (.bashrc, nvm, oh-my-zsh, ...).
#
# Dev Container behavior: a `devcontainerbuilder_devcontainer` data source
# reads the built image's merged devcontainer.json (base image + Features +
# the repo's own config). Its `remoteUser` decides whose home is persisted;
# its lifecycle commands (onCreate/updateContent/postCreate/postStart) run
# from a login-blocking script on every start - a pod's root filesystem is
# fresh each time, so they must be idempotent; and its
# customizations.vscode extensions/settings are installed into
# ~/.vscode-server, where VS Code Desktop picks them up.
terraform {
  # check blocks (1.5).
  required_version = ">= 1.5.0"
  required_providers {
    coder = {
      source = "coder/coder"
      # coder_parameter's form_type (2.4.0, fixed in 2.5.0); the vscode-web
      # and vscode-desktop modules need >= 2.5 too.
      version = ">= 2.5.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # The pod security context's fs_group_change_policy (2.16.0).
      version = ">= 2.16.0"
    }
    devcontainerbuilder = {
      source = "deepspacecartel/devcontainer-builder"
      # >= 0.3.0 for the data source's runtime/env_scripts/variables (and a
      # devcontainer-builder service >= 0.3.0 behind it); < 2.0.0 because a
      # major version may change the schema this template uses.
      version = ">= 0.3.0, < 2.0.0"
    }
  }
}

provider "coder" {
}

# --- Template-level variables -----------------------------------------
# Set once, when this template is pushed/configured in Coder (`coder
# templates push -var ...`) - not per-workspace. See the guide for where
# each of these values actually comes from.

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces. A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspace Deployments in (must exist prior to creating workspaces)."
}

variable "devcontainer_builder_endpoint" {
  type        = string
  description = "Base URL of an already-running devcontainer-builder instance, e.g. http://devcontainer-builder.devcontainer-builder.svc.cluster.local:8080. This template never deploys devcontainer-builder or BuildKit itself - both are cluster-level platform infrastructure, set up once before this template is ever pushed. See the guide."
}

variable "image_pull_secret_name" {
  type        = string
  description = "Name of an existing Kubernetes Secret (kubernetes.io/dockerconfigjson) in `namespace`, used as an imagePullSecret for the built image. Leave empty if the registry allows anonymous pulls from your cluster's nodes."
  default     = ""
}

variable "accept_vscode_license" {
  type        = bool
  description = "Accept Microsoft's VS Code Server license (https://aka.ms/vscode-server-license) on behalf of this template's users, enabling VS Code in the browser (vscode-web, extensions from the Microsoft Marketplace). The terms allow use within your own organization; set false if workspaces are offered to others. VS Code Desktop is unaffected."
  default     = true
}

variable "allow_privileged" {
  type        = bool
  description = "Honor devcontainer.json's `privileged: true`, `--security-opt seccomp=unconfined` and capabilities beyond Pod Security baseline's list (e.g. SYS_PTRACE, NET_ADMIN). Off by default: they need a namespace whose Pod Security level allows them, and privileged pods can take over their node."
  default     = false
}

variable "subdomain_apps" {
  type        = bool
  description = "Serve VS Code in the browser and the forwarded-port apps on their own subdomains (Coder's recommendation). They need a wildcard access URL on the Coder deployment (CODER_WILDCARD_ACCESS_URL, https://coder.com/docs/admin/networking/wildcard-access-url); set false without one, and they're served on paths of the main Coder URL instead."
  default     = true
}

variable "max_forwarded_ports" {
  type        = number
  description = "How many of devcontainer.json's forwardPorts get a dashboard app. Coder needs a fixed number of app slots; unused ones are hidden."
  default     = 10
}

variable "vscode_extension" {
  type        = string
  description = "devcontainer-builder's VS Code extension (\"Dev Containers for Coder in K8S\"), installed into every workspace's VS Code: it offers to rebuild the workspace when the branch's Dev Container configuration changes on origin, and to add one where there's none. A Marketplace ID, or the http(s):// URL of a VSIX (e.g. an unreleased build). Empty to not install it."
  default     = "deepspacecartel.devcontainer-builder"
}

variable "external_auth_id" {
  type        = string
  description = "ID of a Coder external auth provider for the git host (e.g. \"github\", see https://coder.com/docs/admin/external-auth), for private repositories. When set, creating a workspace asks the user to link that account, the workspace's clone uses it (the agent's GIT_ASKPASS), and so does the image build: the user's own token is sent to devcontainer-builder instead of service-side gitCredentials. Empty: public repositories, or credentials configured on devcontainer-builder or below."
  default     = ""
}

variable "max_cpu" {
  type        = number
  description = "Most CPU cores a repository's hostRequirements.cpus can reserve (requests) - above it, the workspace gets this many and a warning."
  default     = 8
}

variable "max_memory" {
  type        = number
  description = "Most memory, in GiB, a repository's hostRequirements.memory can reserve (requests) - above it, the workspace gets this much and a warning."
  default     = 32
}

variable "git_credentials_username" {
  type        = string
  description = "Optional HTTPS git username, used for every workspace built from this template. Leave empty for public repositories only - devcontainer-builder's own server-side gitCredentials (configured once on the service itself) is the better place for per-host credentials that should apply regardless of which template/caller is asking."
  default     = ""
}

variable "git_credentials_token" {
  type        = string
  description = "Optional HTTPS git token/password, paired with git_credentials_username."
  default     = ""
  sensitive   = true
}

# --- Workspace parameters -----------------------------------------------
# What the person creating a workspace from this template actually fills
# in - this is the whole point of this template over the raw HTTP API or
# the bare Terraform module/provider used directly: type a repo URL, get a
# running workspace.

data "coder_parameter" "repository" {
  name         = "repository"
  display_name = "Git repository"
  order        = 1
  description  = "The git repository to work on: https://, ssh://, or SCP-style (git@host:path). Its .devcontainer/devcontainer.json (or .devcontainer.json) defines the workspace; without one, it gets devcontainer-builder's fallback image."
  icon         = "/icon/git.svg"
  mutable      = false
}

data "coder_parameter" "branch" {
  name         = "branch"
  display_name = "Branch"
  order        = 2
  description  = "Branch to build."
  default      = "main"
  icon         = "/icon/git.svg"
  mutable      = false
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  order        = 3
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  order        = 4
  description  = "The amount of memory in GiB"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 GiB"
    value = "2"
  }
  option {
    name  = "4 GiB"
    value = "4"
  }
  option {
    name  = "6 GiB"
    value = "6"
  }
  option {
    name  = "8 GiB"
    value = "8"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk size"
  order        = 5
  description  = "The size of the persistent disk (home + /workspaces) in GiB, set when the workspace is created"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
}

# ${localEnv:NAME} in devcontainer.json refers to the developer's machine,
# which a workspace doesn't have - values come from here instead. Coder
# can't create one parameter per variable (parameters can't depend on the
# image), so it's one free-form parameter; the "Dev Container variables"
# metadata item lists what the image uses and what's still unset.
data "coder_parameter" "devcontainer_variables" {
  name         = "devcontainer_variables"
  display_name = "Dev Container variables"
  order        = 6
  description  = "Values for $${localEnv:NAME} in the repository's devcontainer.json: one NAME=value per line. Changes apply on the next restart. Visible to anyone who can see this workspace's settings."
  type         = "string"
  form_type    = "textarea"
  default      = ""
  mutable      = true
  icon         = "/icon/docker.svg"
}

# Bump to rebuild the image from the branch's latest commit on the next
# start. The working copy in /workspaces is left as it is.
data "coder_parameter" "rebuild" {
  name         = "rebuild"
  display_name = "Rebuild"
  order        = 7
  description  = "Increase to rebuild the image from the branch's latest commit on the next start (e.g. after devcontainer.json changes). Your working copy is not touched."
  type         = "number"
  default      = 0
  mutable      = true
  icon         = "/icon/docker.svg"
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

provider "devcontainerbuilder" {
  endpoint = var.devcontainer_builder_endpoint
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  # Only read while the workspace is starting (count = start_count below),
  # so stopping a workspace never depends on devcontainer-builder being up.
  dc = one(data.devcontainerbuilder_devcontainer.workspace[*])

  # The user tools, IDEs and hooks run as (remoteUser, else containerUser,
  # else the image's USER, else root - resolved by devcontainer-builder)
  # and its uid/gid/home, recorded by the build: the pod runs as that user
  # from the start, and that home is persisted.
  remote_user = try(coalesce(local.dc.remote_user, local.dc.container_user), "root")
  runtime     = try(local.dc.runtime, null)
  # An image built before devcontainer-builder 0.3.0 has no recorded
  # account. Fall back to uid/gid 1000 - what this template used before it
  # recorded them - so a workspace upgraded from an older template version
  # still starts (with a warning) and can then be rebuilt: Rebuild only
  # takes effect once a start has succeeded on this template version
  # (replace_triggered_by doesn't fire when terraform_data.rebuild is
  # created, only when it changes).
  recorded_uid = try(local.runtime.remote_user_uid, null)
  recorded_gid = try(local.runtime.remote_user_gid, null)
  uid          = local.recorded_uid != null ? local.recorded_uid : 1000
  gid          = local.recorded_gid != null ? local.recorded_gid : 1000
  home_dir     = try(coalesce(local.runtime.remote_user_home), local.remote_user == "root" ? "/root" : "/home/${local.remote_user}")

  lifecycle_scripts = try(local.dc.lifecycle_scripts, {})
  env_scripts       = try(local.dc.env_scripts, {})
  vscode_extensions = try(local.dc.extensions, [])
  vscode_settings   = try(local.dc.settings_json, "{}")
  host_requirements = try(local.dc.host_requirements, null)
  warnings          = try(local.dc.warnings, [])
  variables         = try(local.dc.variables, [])

  # devcontainer.json's workspaceFolder (default: Dev Containers'
  # "Clone Repository in Container Volume" convention,
  # /workspaces/<repo name>), with the workspace placeholders filled in.
  # The repository is cloned there.
  repo_name            = trimsuffix(basename(trimsuffix(data.coder_parameter.repository.value, "/")), ".git")
  raw_workspace_folder = coalesce(try(local.dc.workspace_folder, null), "/workspaces/$${localWorkspaceFolderBasename}")
  workspace_folder = replace(replace(replace(local.raw_workspace_folder,
    "$${localWorkspaceFolderBasename}", local.repo_name),
    "$${containerWorkspaceFolderBasename}", local.repo_name),
  "$${devcontainerId}", data.coder_workspace.me.id)

  # The workspace folder gets its own directory on the PVC unless it's
  # already persisted by the /workspaces mount (at or below it) - or is the
  # home itself, which a second mount at the same path would collide with.
  workspace_folder_mounted = !(local.workspace_folder == "/workspaces" || startswith(local.workspace_folder, "/workspaces/") || local.workspace_folder == local.home_dir)

  # Mount targets may use the workspace placeholders too.
  requested_mounts = [for i, m in try(local.dc.mounts, []) : merge(m, {
    index = i
    target = replace(replace(replace(replace(m.target,
      "$${containerWorkspaceFolder}", local.workspace_folder),
      "$${localWorkspaceFolder}", local.workspace_folder),
      "$${containerWorkspaceFolderBasename}", basename(local.workspace_folder)),
    "$${localWorkspaceFolderBasename}", basename(local.workspace_folder))
  })]
  # A pod with two volume mounts at the same path is rejected, so a mount
  # whose target is one of the template's own mount points (or an earlier
  # mount's target) is dropped, with a warning. Compared without a
  # trailing slash.
  reserved_mount_paths = compact(["/workspaces", local.home_dir, "/dev/shm", local.workspace_folder_mounted ? local.workspace_folder : ""])
  mount_keys           = [for m in local.requested_mounts : trimsuffix(m.target, "/")]
  mount_collides = [for i, key in local.mount_keys :
    contains(local.reserved_mount_paths, key) || contains(slice(local.mount_keys, 0, i), key)
  ]
  mounts           = [for i, m in local.requested_mounts : m if !local.mount_collides[i]]
  colliding_mounts = [for i, m in local.requested_mounts : m if local.mount_collides[i]]
  mount_warnings = [for m in local.colliding_mounts :
    "mounts: the ${m.kind} mount at ${m.target} is not mounted - that path is already a mount point (the home, /workspaces, the workspace folder, /dev/shm or another mount)"
  ]
  volume_mounts = [for m in local.mounts : m if m.kind == "volume"]
  tmpfs_mounts  = [for m in local.mounts : m if m.kind == "tmpfs"]
  # PVC directory per named volume (volumes/<source>); anonymous volumes
  # get one per position.
  volume_dirs = [for m in local.volume_mounts : "volumes/${coalesce(m.source, "anonymous-${m.index}")}"]

  ports = try(local.dc.forward_ports, [])

  # hostRequirements are minimums, as in the spec: the scheduler reserves
  # them (requests, capped by var.max_cpu/max_memory), and the limits are
  # the larger of them and the CPU/Memory parameters. Storage is the larger
  # of it and the Disk parameter, so the PVC never shrinks. Where the
  # parameter wins, values stay "<n>Gi" as before (no spurious diffs).
  gib            = 1073741824
  param_cpu      = tonumber(data.coder_parameter.cpu.value)
  param_memory   = tonumber(data.coder_parameter.memory.value) * local.gib
  param_disk     = tonumber(data.coder_parameter.disk_size.value) * local.gib
  required_cpu   = try(local.host_requirements.cpus, null)
  required_mem   = try(local.host_requirements.memory_bytes, null)
  required_disk  = try(local.host_requirements.storage_bytes, null)
  reserved_cpu   = local.required_cpu != null ? min(local.required_cpu, var.max_cpu) : null
  reserved_mem   = local.required_mem != null ? floor(min(local.required_mem, var.max_memory * local.gib)) : null
  cpu_request    = local.reserved_cpu != null ? tostring(local.reserved_cpu) : "250m"
  memory_request = local.reserved_mem != null ? tostring(local.reserved_mem) : "512Mi"
  cpu_limit      = local.reserved_cpu != null && try(local.reserved_cpu > local.param_cpu, false) ? tostring(local.reserved_cpu) : data.coder_parameter.cpu.value
  memory_limit   = local.reserved_mem != null && try(local.reserved_mem > local.param_memory, false) ? tostring(local.reserved_mem) : "${data.coder_parameter.memory.value}Gi"
  disk_size      = local.required_disk != null && try(local.required_disk > local.param_disk, false) ? tostring(floor(local.required_disk)) : "${data.coder_parameter.disk_size.value}Gi"
  resource_warnings = concat(
    local.required_cpu != null && try(local.required_cpu > var.max_cpu, false) ? ["hostRequirements.cpus ${local.required_cpu} is more than this template allows (max_cpu ${var.max_cpu}) - reserving ${var.max_cpu}"] : [],
    local.required_mem != null && try(local.required_mem > var.max_memory * local.gib, false) ? ["hostRequirements.memory ${format("%.1f", local.required_mem / local.gib)} GiB is more than this template allows (max_memory ${var.max_memory} GiB) - reserving ${var.max_memory} GiB"] : [],
  )
  # What the workspace got, for the agent metadata: reserved/limit, and
  # whether devcontainer.json's hostRequirements set the reservation.
  resources_summary = join(" · ", [
    "CPU ${local.cpu_request} / ${local.cpu_limit}",
    "memory ${local.memory_request} / ${local.memory_limit}",
    "disk ${local.disk_size}",
    local.required_cpu != null || local.required_mem != null || local.required_disk != null ? "from hostRequirements" : "from the parameters",
  ])
  gpu_json = try(local.host_requirements.gpu_json, null)
  # gpu: true or {cores, memory} -> one GPU; "optional" or unset -> none.
  gpu_limit = local.gpu_json != null && local.gpu_json != "\"optional\"" && local.gpu_json != "false" ? { "nvidia.com/gpu" = "1" } : {}

  # Pod Security "baseline" (the usual namespace level) only allows these
  # added capabilities; anything else (SYS_PTRACE, NET_ADMIN, ...) would get
  # the whole pod rejected, so it's only added with var.allow_privileged.
  baseline_capabilities  = ["AUDIT_WRITE", "CHOWN", "DAC_OVERRIDE", "FOWNER", "FSETID", "KILL", "MKNOD", "NET_BIND_SERVICE", "SETFCAP", "SETGID", "SETPCAP", "SETUID", "SYS_CHROOT"]
  requested_capabilities = try(local.runtime.cap_add, [])
  capabilities           = var.allow_privileged ? local.requested_capabilities : [for c in local.requested_capabilities : c if contains(local.baseline_capabilities, c)]
  skipped_capabilities   = var.allow_privileged ? [] : [for c in local.requested_capabilities : c if !contains(local.baseline_capabilities, c)]
  all_warnings = concat(local.warnings, local.resource_warnings, local.mount_warnings, length(local.skipped_capabilities) > 0 ? [
    "capAdd ${join(", ", local.skipped_capabilities)} not added - Pod Security baseline forbids it (template variable allow_privileged enables it)"
    ] : [], local.dc != null && local.recorded_uid == null ? [
    "the image doesn't record its remote user's uid/gid (built by devcontainer-builder older than 0.3.0) - running as uid/gid 1000; bump the Rebuild parameter to rebuild it"
  ] : [])

  # Mount points that live on the PVC (the workspace folder itself, and any
  # mount target inside /workspaces, the home or the workspace folder):
  # seed-home creates them as the remote user first, or kubelet would
  # create them root-owned and unwritable (e.g. the workspace folder, when
  # a volume is mounted at <workspace folder>/node_modules).
  mount_point_dirs = compact([for t in concat([local.workspace_folder], [for m in local.mounts : m.target]) :
    startswith(t, "/workspaces/") ? "workspaces/${trimprefix(t, "/workspaces/")}" :
    startswith(t, "${local.home_dir}/") ? "home/${trimprefix(t, "${local.home_dir}/")}" :
    local.workspace_folder_mounted && startswith(t, "${local.workspace_folder}/") ? "workspace-folder/${trimprefix(t, "${local.workspace_folder}/")}" : ""
  ])

  # localEnv variables without a default that the user must provide -
  # ignoring ones only used by mounts, which only matter for bind mounts
  # (dropped anyway: there's no host).
  # Only shell-safe names (the service only reports those, but they end up
  # in a shell script and a regex below, so it's checked here too).
  required_variables = [for v in local.variables : v.name if v.kind == "localEnv" && v.default == null && can(regex("^[A-Za-z_][A-Za-z0-9_]*$", v.name)) && length([for u in v.used_in : u if !startswith(u, "mounts")]) > 0]
  # Names only - the checks below must never reference the parameter itself:
  # Terraform prints referenced values in a failed check's diagnostics, and
  # the parameter holds the user's tokens.
  missing_variables = nonsensitive([for name in local.required_variables : nonsensitive(name) if !can(regex("(?m)^${name}=.+", data.coder_parameter.devcontainer_variables.value))])
  # Not secrets, but derived from the data source (whose registry
  # credentials input is sensitive) - unmarked so the build log shows them.
  warning_lines = nonsensitive([for w in local.all_warnings : nonsensitive(w)])

  # Values written into the scripts below as single-quoted shell words
  # ('...' with each ' as '\''): they come from the user's parameters and
  # the repository's devcontainer.json, so they may contain anything.
  sh_workspace_folder = "'${replace(local.workspace_folder, "'", "'\\''")}'"
  sh_repository       = "'${replace(data.coder_parameter.repository.value, "'", "'\\''")}'"
  sh_branch           = "'${replace(data.coder_parameter.branch.value, "'", "'\\''")}'"
  sh_own_extension    = "'${replace(var.vscode_extension, "'", "'\\''")}'"
  # One extension ID per line.
  sh_extensions = "'${replace(join("\n", local.vscode_extensions), "'", "'\\''")}'"

  # Where the lifecycle script records its exit status: on the pod's root
  # filesystem, which is fresh on every start (unlike the home).
  lifecycle_status_file = "/tmp/devcontainer-lifecycle.status"

  # The architecture the agent binary, the image and the node agree on.
  arch = "amd64"

  # This workspace's own image tag. Without one, the tag is sha-<commit>,
  # shared by every workspace built from the same repository and commit -
  # and deleting the image (a Rebuild, or deleting the workspace) would
  # delete it from under the others. The Rebuild value is part of it so a
  # rebuilt image never reuses a tag a node may have cached (the pod pulls
  # IfNotPresent). Lowercase, OCI tag characters only, at most 128.
  image_tag = substr(replace(lower("ws-${data.coder_workspace.me.id}-${data.coder_parameter.rebuild.value}"), "/[^a-z0-9_.-]/", "-"), 0, 128)
}

# --- The actual build ----------------------------------------------------
# Runs once per workspace, on `coder create`/whenever the repository or
# branch parameter changes (both are immutable=true above, so in practice
# only on create - see the guide's note on why these aren't mutable).
# Everything registryAuth/gitCredentials-shaped is left to devcontainer-
# builder's own ambient server-side config by default (image_spec.registry
# unset - resolved by the service's own registry mapping rules); the
# git_credentials block below is the one optional exception, for a
# template-wide default rather than requiring registryMapping-style
# server config for git.
resource "terraform_data" "rebuild" {
  input = data.coder_parameter.rebuild.value
}

# The workspace owner's linked git account (var.external_auth_id). With
# count = 0 Coder doesn't ask for it at all.
data "coder_external_auth" "git" {
  count = var.external_auth_id != "" ? 1 : 0
  id    = var.external_auth_id
}

resource "devcontainerbuilder_build" "workspace" {
  repository = data.coder_parameter.repository.value
  branch     = data.coder_parameter.branch.value

  # The image goes to this workspace's own tag (see local.image_tag); its
  # registry and name are still resolved by devcontainer-builder.
  image_spec = {
    tag = local.image_tag
  }

  # A Rebuild bump replaces the build: the old image tag (this workspace's
  # only) is deleted first and the branch's latest commit built under the
  # new one.
  # Credentials are only needed for the build itself: a linked account's
  # token is refreshed over time, and must not replace (rebuild) the image
  # each time it changes. A Rebuild bump builds with the current one.
  lifecycle {
    replace_triggered_by = [terraform_data.rebuild]
    ignore_changes       = [git_credentials]
  }

  # Template-wide credentials win; else the owner's linked account
  # ("oauth2" as the username works for GitHub and GitLab tokens alike).
  # git_credentials is a nested-object attribute (terraform-plugin-framework),
  # not a legacy SDKv2 block - conditionally assign the object itself (or
  # null to omit), not a `dynamic` block.
  git_credentials = var.git_credentials_username != "" ? {
    username = var.git_credentials_username
    token    = var.git_credentials_token
    } : length(data.coder_external_auth.git) > 0 ? {
    username = "oauth2"
    token    = data.coder_external_auth.git[0].access_token
  } : null
}

# The built image's Dev Container metadata - GET /devcontainer on
# devcontainer-builder, read straight from the registry.
data "devcontainerbuilder_devcontainer" "workspace" {
  count    = data.coder_workspace.me.start_count
  registry = devcontainerbuilder_build.workspace.resolved_registry
  name     = devcontainerbuilder_build.workspace.resolved_name
  tag      = devcontainerbuilder_build.workspace.resolved_tag
  platform = "linux/${local.arch}"
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = local.arch
  # No `dir`: it's deprecated, and anything but $HOME breaks Coder Desktop
  # file sync - so terminals/SSH start in $HOME. code-server and
  # vscode_desktop open the repo.

  # The built-in VS Code Desktop button takes its folder from `dir`, so
  # without it VS Code opens in $HOME with no folder - module.vscode_desktop
  # replaces it. Unset display_apps fields keep their defaults.
  display_apps {
    vscode = false
  }

  metadata {
    display_name = "Dev Container variables"
    key          = "7_devcontainer_variables"
    script       = <<-EOT
      missing=""
      for name in ${join(" ", local.required_variables)}; do
        eval "value=\$${DEVCONTAINER_LOCALENV_$name-}"
        [ -n "$value" ] || missing="$missing $name"
      done
      if [ -n "$missing" ]; then echo "unset:$missing"; else echo "all set"; fi
    EOT
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Resources (reserved / limit)"
    key          = "9_resources"
    script       = "echo '${local.resources_summary}'"
    interval     = 3600
    timeout      = 1
  }

  metadata {
    display_name = "Dev Container warnings"
    key          = "8_devcontainer_warnings"
    script       = "echo '${length(local.all_warnings) == 0 ? "none" : "${length(local.all_warnings)} - see the build log"}'"
    interval     = 3600
    timeout      = 1
  }

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
    display_name = "Data Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval     = 60
    timeout      = 1
  }
}

# VS Code in the browser - Microsoft's own VS Code Server (vscode-web),
# not code-server, so extensions come from the Microsoft Marketplace. It
# shares ~/.vscode-server (and so the extensions/settings installed by
# devcontainer_vscode below) with VS Code Desktop. Installed under the
# persisted home.
module "vscode_web" {
  count          = var.accept_vscode_license ? data.coder_workspace.me.start_count : 0
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.6.2"
  agent_id       = coder_agent.main.id
  folder         = local.workspace_folder
  accept_license = true
  install_prefix = "$HOME/.cache/vscode-web"
  subdomain      = var.subdomain_apps
}

# VS Code Desktop, opened on the cloned repo (in place of the agent's
# built-in button - see coder_agent.main's display_apps).
module "vscode_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = local.workspace_folder
}

# devcontainer.json's lifecycle commands, from the image's merged metadata:
# each hook is one script devcontainer-builder already rendered with the
# Dev Containers CLI's semantics (base image, then Features, then
# devcontainer.json; string/array/object forms; stop at the first failure).
# Clones the repo first (see below), then runs them in the spec's order
# from the repo folder, before login. In Dev Containers the first three run once per
# container; here every start is a fresh root filesystem, so all four run
# on every start and must be idempotent. Output is in the agent's startup
# logs. Its exit status goes to local.lifecycle_status_file (on the pod's
# own filesystem, so never left over from an earlier start), which
# postAttachCommand waits for.
resource "coder_script" "devcontainer_lifecycle" {
  count              = data.coder_workspace.me.start_count
  agent_id           = coder_agent.main.id
  display_name       = "Dev Container lifecycle"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = true
  script             = <<-EOT
    #!/bin/sh
    set -u
    status_file='${local.lifecycle_status_file}'
    rm -f "$status_file"
    trap 'rc=$?; echo "$rc" > "$status_file.tmp" && mv -f "$status_file.tmp" "$status_file"; exit "$rc"' EXIT
    workspace_folder=${local.sh_workspace_folder}
    dir="$HOME/.cache/devcontainer-lifecycle"
    mkdir -p "$dir"

    # Clone the repository into the workspace folder on first start, at
    # the commit the image was built from (on its branch), so the hooks
    # below run the scripts that image was built for. git init + fetch
    # rather than `git clone`: the folder may already hold mount points
    # (e.g. a node_modules volume). Private repos authenticate like the
    # agent: GIT_ASKPASS (Coder external auth) for HTTPS, `coder gitssh`
    # for SSH.
    #
    # A finished clone is marked with .git/devcontainer-cloned, and is never
    # touched again. A .git without the marker is either a working copy
    # (HEAD has a commit - e.g. cloned by an older template version: kept,
    # and marked) or a clone that was cut short before its checkout
    # finished (HEAD unborn: removed and retried).
    repository=${local.sh_repository}
    branch=${local.sh_branch}
    commit='${devcontainerbuilder_build.workspace.commit != null ? devcontainerbuilder_build.workspace.commit : ""}'
    git_dir="$workspace_folder/.git"
    cloned_marker="$git_dir/devcontainer-cloned"
    retry=false
    if [ -d "$git_dir" ] && [ ! -e "$cloned_marker" ]; then
      if git -C "$workspace_folder" rev-parse --verify -q HEAD >/dev/null 2>&1; then
        touch "$cloned_marker"
      else
        echo "devcontainer: $workspace_folder has an unfinished clone, starting over"
        rm -rf "$git_dir"
        retry=true
      fi
    fi
    if [ ! -e "$git_dir" ]; then
      if ! command -v git >/dev/null 2>&1; then
        echo "devcontainer: the image has no git, so $repository can't be cloned - add the git Feature (\"ghcr.io/devcontainers/features/git:1\": {}) to devcontainer.json's features, and rebuild" >&2
        exit 1
      fi
      case "$repository" in
        ssh://* | *@*:*)
          host=$(printf '%s' "$repository" | sed -E 's#^ssh://##; s#^[^@]*@##; s#[:/].*$##')
          mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/known_hosts"
          ssh-keygen -F "$host" -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1 || ssh-keyscan -H -- "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
          ;;
      esac
      echo "devcontainer: cloning $repository ($branch) into $workspace_folder"
      mkdir -p "$workspace_folder"
      # `init` + symbolic-ref rather than `init -b`, which needs git 2.28.
      git -C "$workspace_folder" init -q &&
        git -C "$workspace_folder" symbolic-ref HEAD "refs/heads/$branch" &&
        git -C "$workspace_folder" remote add origin "$repository" &&
        git -C "$workspace_folder" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" || {
          echo "devcontainer: cloning $repository failed" >&2
          rm -rf "$git_dir"
          exit 1
        }
      target="origin/$branch"
      if [ -n "$commit" ] && { git -C "$workspace_folder" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$workspace_folder" fetch -q origin "$commit"; }; then
        target="$commit"
      fi
      # A retry overwrites the files the interrupted checkout already
      # wrote. A first checkout doesn't: files that were already in the
      # folder and are in the way fail it (git lists them), and its .git is
      # removed, so the next start tries the same way again.
      force=""
      if [ "$retry" = true ]; then force="-f"; fi
      if ! git -C "$workspace_folder" checkout -q $force -B "$branch" "$target"; then
        echo "devcontainer: checking out $target in $workspace_folder failed" >&2
        [ "$retry" = true ] || rm -rf "$git_dir"
        exit 1
      fi
      git -C "$workspace_folder" branch -q --set-upstream-to="origin/$branch" "$branch" ||
        echo "devcontainer: couldn't set origin/$branch as $branch's upstream" >&2
      touch "$cloned_marker"
      echo "devcontainer: checked out $(git -C "$workspace_folder" rev-parse --short HEAD), the commit the image was built from"
    fi

    run_hook() {
      [ -n "$2" ] || return 0
      echo "$2" | base64 -d > "$dir/$1.sh" || return 1
      (cd "$workspace_folder" && sh "$dir/$1.sh")
    }

    # initializeCommand runs on the host before the container exists in Dev
    # Containers; here it's simply the first hook.
    run_hook initializeCommand '${base64encode(lookup(local.lifecycle_scripts, "initializeCommand", ""))}' || exit $?
    run_hook onCreateCommand '${base64encode(lookup(local.lifecycle_scripts, "onCreateCommand", ""))}' || exit $?
    run_hook updateContentCommand '${base64encode(lookup(local.lifecycle_scripts, "updateContentCommand", ""))}' || exit $?
    run_hook postCreateCommand '${base64encode(lookup(local.lifecycle_scripts, "postCreateCommand", ""))}' || exit $?
    run_hook postStartCommand '${base64encode(lookup(local.lifecycle_scripts, "postStartCommand", ""))}' || exit $?
  EOT
}

# postAttachCommand runs each time a tool attaches in Dev Containers. There
# is no attach event here, so it runs once per start - without blocking
# login, after the lifecycle script above has succeeded (as in Dev
# Containers, where it follows postStartCommand). Gives up after 30 minutes.
resource "coder_script" "devcontainer_post_attach" {
  # Always present (count can't depend on the image's metadata, which is
  # unknown until the first build) - exits at once if no hook is set.
  count              = data.coder_workspace.me.start_count
  agent_id           = coder_agent.main.id
  display_name       = "Dev Container postAttachCommand"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -u
    hook='${base64encode(lookup(local.lifecycle_scripts, "postAttachCommand", ""))}'
    [ -n "$hook" ] || exit 0
    workspace_folder=${local.sh_workspace_folder}
    status_file='${local.lifecycle_status_file}'
    echo "devcontainer: waiting for the Dev Container lifecycle script before postAttachCommand"
    waited=0
    until [ -s "$status_file" ]; do
      if [ "$waited" -ge 1800 ]; then
        echo "devcontainer: the Dev Container lifecycle script hasn't finished after 30 minutes, not running postAttachCommand" >&2
        exit 1
      fi
      sleep 2
      waited=$((waited + 2))
    done
    status=$(cat "$status_file")
    if [ "$status" != 0 ]; then
      echo "devcontainer: the Dev Container lifecycle script failed (exit status $status), not running postAttachCommand" >&2
      exit 1
    fi
    script="$HOME/.cache/devcontainer-lifecycle/postAttachCommand.sh"
    mkdir -p "$(dirname "$script")"
    echo "$hook" | base64 -d > "$script"
    cd "$workspace_folder" && sh "$script"
  EOT
}

# customizations.vscode from the image's merged metadata, for VS Code
# Desktop: extensions are installed - from the Microsoft Marketplace - into
# ~/.vscode-server/extensions and settings merged into its Machine
# settings, the same folder Desktop's own remote server uses (home is
# persisted). The installer is Desktop's own server if it has connected
# before, else Microsoft's latest VS Code Server, downloaded once into
# ~/.cache - the same server Desktop downloads on first connect, used here
# only as an installer, never served. Doesn't block login: a Desktop
# window that attaches mid-install sees the rest after a reload.
resource "coder_script" "devcontainer_vscode" {
  # Always present, for the same reason - exits at once if there's nothing
  # to install.
  count              = data.coder_workspace.me.start_count
  agent_id           = coder_agent.main.id
  display_name       = "Dev Container VS Code extensions"
  icon               = "/icon/code.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -u
    extensions=${local.sh_extensions}
    settings_b64='${base64encode(local.vscode_settings)}'
    own_extension=${local.sh_own_extension}
    data_dir="$HOME/.vscode-server"
    if [ -z "$extensions" ] && [ "$settings_b64" = "${base64encode("{}")}" ] && [ -z "$own_extension" ]; then
      exit 0
    fi

    server=$(ls -td "$data_dir"/cli/servers/Stable-*/server 2>/dev/null | head -n 1)
    if [ -z "$server" ] || [ ! -x "$server/bin/code-server" ]; then
      server="$HOME/.cache/vscode-server-installer"
      if [ ! -x "$server/bin/code-server" ]; then
        case "$(uname -m)" in
          x86_64) arch=x64 ;;
          aarch64 | arm64) arch=arm64 ;;
          *) echo "devcontainer: no VS Code Server for $(uname -m), skipping extensions" >&2; exit 0 ;;
        esac
        url="https://update.code.visualstudio.com/latest/server-linux-$arch/stable"
        rm -rf "$server" && mkdir -p "$server"
        if command -v curl >/dev/null 2>&1; then fetch="curl -fsSL"; else fetch="wget -qO-"; fi
        if ! $fetch "$url" | tar -xz -C "$server" --strip-components 1; then
          echo "devcontainer: could not download VS Code Server, skipping extensions" >&2
          rm -rf "$server"
          exit 0
        fi
      fi
    fi

    # devcontainer-builder's own extension (vscode-extension/), always the
    # latest (--force updates it). It was
    # deepspacecartel.devcontainer-builder-rebuild before 0.5.0 - removed,
    # or both would run.
    "$server/bin/code-server" --extensions-dir "$data_dir/extensions" --uninstall-extension deepspacecartel.devcontainer-builder-rebuild >/dev/null 2>&1 || true
    case "$own_extension" in
      "") ;;
      http://* | https://*)
        vsix="$HOME/.cache/devcontainer-builder.vsix"
        if command -v curl >/dev/null 2>&1; then download="curl -fsSL -o"; else download="wget -qO"; fi
        if $download "$vsix.tmp" "$own_extension" && mv "$vsix.tmp" "$vsix"; then
          own_extension="$vsix"
        else
          rm -f "$vsix.tmp"
          echo "devcontainer: could not download $own_extension" >&2
          own_extension=""
        fi
        ;;
    esac
    if [ -n "$own_extension" ]; then
      out=$("$server/bin/code-server" --extensions-dir "$data_dir/extensions" --install-extension "$own_extension" --force 2>&1)
      case "$out" in
        *"Failed Installing"* | *"not found"*) echo "devcontainer: could not install $own_extension: $out" >&2 ;;
        *) echo "devcontainer: $own_extension ready" ;;
      esac
    fi

    printf '%s\n' "$extensions" | while IFS= read -r extension; do
      [ -n "$extension" ] || continue
      out=$("$server/bin/code-server" --extensions-dir "$data_dir/extensions" --install-extension "$extension" 2>&1)
      case "$out" in
        *"Failed Installing"* | *"not found"*) echo "devcontainer: could not install $extension: $out" >&2 ;;
        *) echo "devcontainer: $extension ready" ;;
      esac
    done

    # The repository's settings are defaults: a setting is written only if
    # the Machine settings don't have it yet, or still have the value this
    # script wrote last time (recorded in devcontainer-vscode-settings.applied.json)
    # - so a repository's change reaches settings the user hasn't changed,
    # and the user's own values are never overwritten.
    if [ "$settings_b64" != "${base64encode("{}")}" ]; then
      mkdir -p "$data_dir/data/Machine"
      echo "$settings_b64" | base64 -d > "$HOME/.cache/devcontainer-vscode-settings.json"
      "$server/node" -e '
        const fs = require("fs");
        const [target, incoming, appliedFile] = process.argv.slice(1);
        const read = (file) => fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
        const has = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
        const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
        let current;
        try { current = read(target); }
        catch (e) { console.error("devcontainer: " + target + " is not plain JSON, leaving it unchanged"); process.exit(0); }
        let applied = {};
        try { applied = read(appliedFile); } catch (e) {}
        const repository = read(incoming);
        const written = [];
        for (const [key, value] of Object.entries(repository)) {
          const isDefault = !has(current, key) || (has(applied, key) && same(current[key], applied[key]));
          if (isDefault && !same(current[key], value)) { current[key] = value; written.push(key); }
        }
        if (written.length > 0) fs.writeFileSync(target, JSON.stringify(current, null, 2) + require("os").EOL);
        const nowApplied = {};
        for (const [key, value] of Object.entries(repository)) if (same(current[key], value)) nowApplied[key] = value;
        fs.writeFileSync(appliedFile, JSON.stringify(nowApplied, null, 2) + require("os").EOL);
        console.log("devcontainer: VS Code settings in " + target + ": " + (written.length > 0 ? "set " + written.join(", ") : "nothing to change"));
      ' "$data_dir/data/Machine/settings.json" "$HOME/.cache/devcontainer-vscode-settings.json" "$HOME/.cache/devcontainer-vscode-settings.applied.json"
    fi
  EOT
}

# Everything in devcontainer.json the workspace couldn't honor, as one
# Terraform warning in the workspace's build log (full text, one per line) -
# the agent metadata above only has room for a count.
check "devcontainer_warnings" {
  assert {
    condition     = length(local.warning_lines) == 0
    error_message = "devcontainer.json settings this workspace doesn't honor:\n- ${join("\n- ", local.warning_lines)}"
  }
}

check "devcontainer_variables" {
  assert {
    condition     = length(local.missing_variables) == 0
    error_message = "devcontainer.json uses $${localEnv:...} variables without a value: ${join(", ", local.missing_variables)}. Add NAME=value lines to the workspace's \"Dev Container variables\" setting and restart."
  }
}

# devcontainer.json's forwardPorts as dashboard apps. Coder needs a fixed
# number of apps at plan time, so there are var.max_forwarded_ports slots;
# the ones without a port are hidden.
resource "coder_app" "forwarded_port" {
  count        = data.coder_workspace.me.start_count * var.max_forwarded_ports
  agent_id     = coder_agent.main.id
  slug         = "port-${count.index}"
  display_name = count.index < length(local.ports) ? coalesce(try(local.ports[count.index].label, null), "Port ${try(local.ports[count.index].port, 0)}") : null
  url          = "${try(local.ports[count.index].protocol, "") == "https" ? "https" : "http"}://localhost:${try(local.ports[count.index].port, 0)}"
  icon         = count.index < length(local.ports) ? "/icon/widgets.svg" : null
  subdomain    = var.subdomain_apps
  share        = "owner"
  hidden       = count.index >= length(local.ports)
}

# For the rebuild prompt extension (see devcontainer_vscode): the commit
# the image was built from, compared with origin/<branch>, and the Rebuild
# value it increases.
resource "coder_env" "devcontainer_image_commit" {
  agent_id = coder_agent.main.id
  name     = "DEVCONTAINER_IMAGE_COMMIT"
  value    = devcontainerbuilder_build.workspace.commit != null ? devcontainerbuilder_build.workspace.commit : ""
}

resource "coder_env" "devcontainer_branch" {
  agent_id = coder_agent.main.id
  name     = "DEVCONTAINER_BRANCH"
  value    = data.coder_parameter.branch.value
}

resource "coder_env" "devcontainer_rebuild" {
  agent_id = coder_agent.main.id
  name     = "DEVCONTAINER_REBUILD"
  value    = data.coder_parameter.rebuild.value
}

# Commits made in the workspace are attributed to its owner.
resource "coder_env" "git_author_name" {
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_committer_name" {
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_author_email" {
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

resource "coder_env" "git_committer_email" {
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

resource "kubernetes_persistent_volume_claim_v1" "data" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-data"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.disk_size
      }
    }
  }

  # The size is decided when the workspace is created. Later it would come
  # from the image's hostRequirements while the workspace runs and from the
  # parameter while it's stopped, so changes are ignored: never shrink (or
  # churn) the claim over that. A larger hostRequirements.storage after a
  # rebuild doesn't grow it (not every storage class can expand volumes).
  lifecycle {
    ignore_changes = [spec[0].resources[0].requests]
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.data
  ]

  wait_for_rollout = false
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
        "app.kubernetes.io/part-of"  = "coder"
        "com.coder.resource"         = "true"
        "com.coder.workspace.id"     = data.coder_workspace.me.id
        "com.coder.workspace.name"   = data.coder_workspace.me.name
        "com.coder.user.id"          = data.coder_workspace_owner.me.id
        "com.coder.user.username"    = data.coder_workspace_owner.me.name
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
          "app.kubernetes.io/part-of"  = "coder"
          "com.coder.resource"         = "true"
          "com.coder.workspace.id"     = data.coder_workspace.me.id
          "com.coder.workspace.name"   = data.coder_workspace.me.name
          "com.coder.user.id"          = data.coder_workspace_owner.me.id
          "com.coder.user.username"    = data.coder_workspace_owner.me.name
        }
      }
      spec {
        # Everything runs as the remote user; fsGroup makes the PVC
        # writable for it (OnRootMismatch: only re-owned when the volume
        # root doesn't match, not on every start).
        security_context {
          run_as_user            = local.uid
          run_as_group           = local.gid
          fs_group               = local.gid
          fs_group_change_policy = "OnRootMismatch"
        }

        # devcontainer.json's `init` / --init: the pause container becomes
        # PID 1 and reaps zombies, like Docker's tini.
        share_process_namespace = try(local.runtime.init, false)
        hostname                = try(local.runtime.hostname, null)

        # Only nodes of the agent's (and the image's) architecture.
        node_selector = {
          "kubernetes.io/arch" = local.arch
        }

        dynamic "host_aliases" {
          for_each = try(local.runtime.host_aliases, [])
          content {
            ip        = host_aliases.value.ip
            hostnames = host_aliases.value.hostnames
          }
        }

        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name != "" ? [1] : []
          content {
            name = var.image_pull_secret_name
          }
        }

        # Runs before "dev", with the same image and user: there, the image's
        # own home is still visible (nothing is mounted over it), and the PVC
        # is at /mnt/data. On first start only (marker file), it copies that
        # home into the PVC's home/ - so the subPath mount below doesn't hide
        # the image's dotfiles - and from then on the user's own changes win.
        # It pre-creates every subPath dir (kubelet would create them
        # root-owned).
        init_container {
          name              = "seed-home"
          image             = devcontainerbuilder_build.workspace.image
          image_pull_policy = "IfNotPresent"
          command = ["sh", "-c", <<-EOT
            set -eu
            mkdir -p /mnt/data/home /mnt/data/workspaces /mnt/data/workspace-folder
            for dir in $VOLUME_DIRS $MOUNT_POINT_DIRS; do mkdir -p "/mnt/data/$dir"; done
            # A file that can't be copied (unreadable, a socket, ...) is
            # only a warning: it mustn't keep the workspace from starting.
            # -n (don't overwrite) is in GNU, BusyBox and BSD cp, though
            # some report skipped files as a failure.
            if [ ! -e /mnt/data/home/.devcontainer-home-seeded ]; then
              if [ ! -d "$HOME_DIR" ]; then
                echo "seed-home: $HOME_DIR isn't in the image, starting with an empty home"
              elif cp -R -p -n "$HOME_DIR"/. /mnt/data/home/; then
                echo "seed-home: seeded /mnt/data/home from $HOME_DIR"
              else
                echo "seed-home: warning: some of $HOME_DIR couldn't be copied (see above); seeded the rest"
              fi
              touch /mnt/data/home/.devcontainer-home-seeded
            fi
          EOT
          ]
          env {
            name  = "HOME_DIR"
            value = local.home_dir
          }
          env {
            name  = "VOLUME_DIRS"
            value = join(" ", local.volume_dirs)
          }
          env {
            name  = "MOUNT_POINT_DIRS"
            value = join(" ", local.mount_point_dirs)
          }
          resources {
            requests = {
              "cpu"    = "50m"
              "memory" = "64Mi"
            }
            limits = {
              "cpu"    = "500m"
              "memory" = "256Mi"
            }
          }
          volume_mount {
            mount_path = "/mnt/data"
            name       = "data"
          }
        }

        container {
          name = "dev"
          # The one real change from the upstream coder/kubernetes template
          # - a fixed/parameterized `image` variable becomes the real,
          # pushed image this workspace's own devcontainerbuilder_build
          # resource just built.
          image             = devcontainerbuilder_build.workspace.image
          image_pull_policy = "IfNotPresent"
          # Sets the Dev Container environment (workspace variables, the
          # user's Dev Container variables, then containerEnv and remoteEnv -
          # so `$${PATH}:/x` expands against the image's real PATH), then
          # runs the agent. Everything the agent starts - terminals, IDEs,
          # the lifecycle scripts - inherits that environment.
          command = ["sh", "-c", <<-EOT
            set -eu
            export DEVCONTAINER_WORKSPACE_FOLDER="$DC_WORKSPACE_FOLDER"
            export DEVCONTAINER_WORKSPACE_FOLDER_BASENAME="$(basename "$DC_WORKSPACE_FOLDER")"
            export DEVCONTAINER_ID="$DC_ID"
            while IFS= read -r line || [ -n "$line" ]; do
              case "$line" in '' | '#'*) continue ;; esac
              key="$${line%%=*}"
              case "$key" in '' | *[!A-Za-z0-9_]*) echo "workspace: ignoring Dev Container variable line '$key'" >&2; continue ;; esac
              export "DEVCONTAINER_LOCALENV_$key=$${line#*=}"
            done <<EOF_VARIABLES
            $DC_VARIABLES
            EOF_VARIABLES
            # An unset variable (e.g. a Dev Container variable the user hasn't
            # provided yet) expands to empty, as with the Dev Containers CLI -
            # so no `set -u` while these run.
            set +u
            for script in "$DC_CONTAINER_ENV" "$DC_REMOTE_ENV"; do
              [ -n "$script" ] || continue
              printf '%s' "$script" | base64 -d > /tmp/devcontainer-env.sh
              . /tmp/devcontainer-env.sh
            done
            set -u
            rm -f /tmp/devcontainer-env.sh
            export HOME="$DC_HOME" USER="$DC_REMOTE_USER" LOGNAME="$DC_REMOTE_USER"
            init="$DC_INIT_SCRIPT"
            unset DC_WORKSPACE_FOLDER DC_ID DC_VARIABLES DC_CONTAINER_ENV DC_REMOTE_ENV DC_REMOTE_USER DC_INIT_SCRIPT DC_HOME
            exec sh -c "$init"
          EOT
          ]
          security_context {
            privileged = var.allow_privileged && try(local.runtime.privileged, false)
            capabilities {
              add = local.capabilities
            }
            dynamic "seccomp_profile" {
              for_each = var.allow_privileged && try(local.runtime.seccomp_unconfined, false) ? [1] : []
              content {
                type = "Unconfined"
              }
            }
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "DC_INIT_SCRIPT"
            value = coder_agent.main.init_script
          }
          env {
            name  = "DC_REMOTE_USER"
            value = local.remote_user
          }
          env {
            name  = "DC_HOME"
            value = local.home_dir
          }
          env {
            name  = "DC_WORKSPACE_FOLDER"
            value = local.workspace_folder
          }
          env {
            name  = "DC_ID"
            value = data.coder_workspace.me.id
          }
          env {
            name  = "DC_VARIABLES"
            value = data.coder_parameter.devcontainer_variables.value
          }
          env {
            name  = "DC_CONTAINER_ENV"
            value = base64encode(lookup(local.env_scripts, "containerEnv", ""))
          }
          env {
            name  = "DC_REMOTE_ENV"
            value = base64encode(lookup(local.env_scripts, "remoteEnv", ""))
          }
          resources {
            requests = {
              "cpu"    = local.cpu_request
              "memory" = local.memory_request
            }
            limits = merge({
              "cpu"    = local.cpu_limit
              "memory" = local.memory_limit
            }, local.gpu_limit)
          }
          volume_mount {
            mount_path = local.home_dir
            name       = "data"
            sub_path   = "home"
            read_only  = false
          }
          volume_mount {
            mount_path = "/workspaces"
            name       = "data"
            sub_path   = "workspaces"
            read_only  = false
          }
          # A workspaceFolder outside /workspaces (and not the home itself)
          # gets its own directory on the PVC; otherwise this mount points at
          # an unused path.
          volume_mount {
            mount_path = local.workspace_folder_mounted ? local.workspace_folder : "/mnt/.devcontainer-unused-workspace-folder"
            name       = "data"
            sub_path   = "workspace-folder"
            read_only  = false
          }
          # devcontainer.json's volume mounts, persisted on the PVC.
          dynamic "volume_mount" {
            for_each = local.volume_mounts
            content {
              mount_path = volume_mount.value.target
              name       = "data"
              sub_path   = "volumes/${coalesce(volume_mount.value.source, "anonymous-${volume_mount.value.index}")}"
              read_only  = volume_mount.value.read_only
            }
          }
          dynamic "volume_mount" {
            for_each = local.tmpfs_mounts
            content {
              mount_path = volume_mount.value.target
              name       = "tmpfs-${volume_mount.value.index}"
            }
          }
          volume_mount {
            mount_path = "/dev/shm"
            name       = "dshm"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata.0.name
            read_only  = false
          }
        }

        # /dev/shm sized from runArgs --shm-size (Docker's default is 64 MiB).
        volume {
          name = "dshm"
          empty_dir {
            medium     = "Memory"
            size_limit = try(local.runtime.shm_size_bytes, null) != null ? tostring(local.runtime.shm_size_bytes) : "64Mi"
          }
        }

        dynamic "volume" {
          for_each = local.tmpfs_mounts
          content {
            name = "tmpfs-${volume.value.index}"
            empty_dir {
              medium = "Memory"
            }
          }
        }

        affinity {
          # Spreads workspace pods evenly across nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
