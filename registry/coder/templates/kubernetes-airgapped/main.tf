# An air-gapped Kubernetes starter template.
#
# Nothing in this template reaches the public internet at build time or at
# workspace startup:
#
# - No remote Terraform modules (no registry.coder.com sources).
# - Providers are pinned so they can be served from a filesystem or network
#   mirror on the provisioner.
# - The workspace image is pulled from your internal registry.
# - IDEs are expected to be baked into the image. No install scripts run at
#   startup.
# - The agent binary is downloaded from your Coder deployment's access URL,
#   not from GitHub.
#
# See the README for how to mirror providers and build the workspace image.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

provider "coder" {
}

variable "use_kubeconfig" {
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  type        = bool
  default     = false
}

variable "namespace" {
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
  type        = string
}

variable "image" {
  description = <<-EOF
  Fully qualified workspace image in your internal registry, for example
  "registry.example.internal/coder/workspace:ubuntu". The image must contain
  curl or wget (used to fetch the agent from your Coder deployment) and any
  IDEs you want to offer, such as code-server. See the README for an example
  Dockerfile.
  EOF
  type        = string
  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "Set image to a workspace image hosted in your internal registry."
  }
}

variable "image_pull_secret" {
  description = "Name of an existing Kubernetes Secret (of type kubernetes.io/dockerconfigjson) in the workspace namespace used to pull the workspace image from your internal registry. Leave empty if the registry doesn't require authentication or the namespace's default ServiceAccount already has pull credentials."
  type        = string
  default     = ""
}

variable "code_server_enabled" {
  description = "Start code-server from the workspace image and expose it as a web IDE. code-server must already be installed in the image; this template never downloads it."
  type        = bool
  default     = true
}

variable "extensions_gallery" {
  description = <<-EOF
  Optional JSON value for code-server's EXTENSIONS_GALLERY environment
  variable, pointing at an internal extension marketplace mirror, for example
  {"serviceUrl":"https://openvsx.example.internal/vscode/gallery","itemUrl":"https://openvsx.example.internal/vscode/item"}.
  Leave empty to disable the marketplace.
  EOF
  type        = string
  default     = ""
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
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
  description  = "The amount of memory in GB"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  code_server_port = 13337
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  env = var.extensions_gallery == "" ? {} : {
    EXTENSIONS_GALLERY = var.extensions_gallery
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
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
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# Starts the code-server binary that ships in the workspace image. Unlike the
# code-server registry module, this never downloads code-server, so it works
# with no outbound network access.
resource "coder_script" "code_server" {
  count        = var.code_server_enabled ? 1 : 0
  agent_id     = coder_agent.main.id
  display_name = "code-server"
  icon         = "/icon/code.svg"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env sh
    set -eu

    if ! command -v code-server > /dev/null 2>&1; then
      echo "code-server is not installed in this workspace image."
      echo "Bake it into the image (see the template README) or set code_server_enabled = false."
      exit 1
    fi

    code-server \
      --auth none \
      --bind-addr "127.0.0.1:${local.code_server_port}" \
      --disable-telemetry \
      --disable-update-check \
      --disable-workspace-trust \
      "$HOME" > /tmp/code-server.log 2>&1 &
  EOT
}

resource "coder_app" "code_server" {
  count        = var.code_server_enabled ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:${local.code_server_port}/?folder=/home/coder"
  subdomain    = false
  share        = "owner"
  order        = 1

  healthcheck {
    url       = "http://localhost:${local.code_server_port}/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace_owner.me.id
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
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
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home
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
        security_context {
          run_as_user     = 1000
          fs_group        = 1000
          run_as_non_root = true
        }

        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret == "" ? [] : [var.image_pull_secret]
          content {
            name = image_pull_secrets.value
          }
        }

        container {
          name = "dev"
          # Pulled from your internal registry. IfNotPresent avoids a registry
          # round trip on every workspace start once the image is cached.
          image             = var.image
          image_pull_policy = "IfNotPresent"
          # The init script downloads the agent binary from your Coder
          # deployment's access URL, so the only egress the Pod needs is to
          # Coder itself.
          command = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
            read_only  = false
          }
        }

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
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
