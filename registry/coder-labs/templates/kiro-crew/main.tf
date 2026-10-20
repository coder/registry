terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.37"
    }
  }
}

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
  description = "Kubernetes namespace to create workspaces in. The namespace must exist before workspaces are created."
  default     = "coder"
}

variable "service_account_name" {
  type        = string
  description = "Optional Kubernetes service account for workspace pods, for example one mapped to an IAM role. Leave empty to use the namespace's default service account."
  default     = ""
}

variable "image" {
  type        = string
  description = <<-EOF
  Container image for workspaces. The default pins codercom/enterprise-base
  to Ubuntu 24.04 (Python 3.12). Images whose system Python is 3.13 or newer
  ship a pipx that breaks the Kiro Crew installer.
  EOF
  default     = "codercom/enterprise-base@sha256:16031b4de2e099884ad6b4057bffeaf03380a76eddf46c193b5d0767e738ba96"
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences.
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

locals {
  home_dir = "/home/coder"
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  description  = "CPU core limit for the workspace."
  type         = "number"
  form_type    = "input"
  icon         = "/icon/memory.svg"
  default      = 2
  mutable      = true
  order        = 1
  validation {
    min = 2
    max = 8
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Memory limit for the workspace, in GB. The Kiro Crew gateway and its agents can use several GB."
  type         = "number"
  form_type    = "input"
  icon         = "/icon/memory.svg"
  default      = 8
  mutable      = true
  order        = 2
  validation {
    min = 4
    max = 16
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size (GB)"
  description  = "Size of the persistent volume mounted at ${local.home_dir}, in GB. It can only grow."
  type         = "number"
  form_type    = "slider"
  icon         = "/icon/database.svg"
  default      = 30
  mutable      = true
  order        = 3
  validation {
    min       = 10
    max       = 50
    monotonic = "increasing"
  }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository"
  description  = "Optional repository to clone into the workspace on start. Leave empty to skip."
  type         = "string"
  icon         = "/icon/git.svg"
  default      = ""
  mutable      = true
  order        = 4
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  # The agent expands $PATH, so the agent's own directory (and the coder
  # binary that module scripts call) stays on PATH.
  env = {
    PATH = "${local.home_dir}/.local/bin:${local.home_dir}/bin:$PATH"
  }

  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = false
  }

  # The Kiro Crew gateway and its agent subprocesses can be CPU, memory, and
  # disk intensive, so surface usage on the workspace page.
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
    script       = "coder stat disk --path ${local.home_dir}"
    interval     = 60
    timeout      = 1
  }

  startup_script_behavior = "blocking"
  startup_script          = file("${path.module}/startup.sh")
}

module "coder-login" {
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "code-server" {
  source    = "registry.coder.com/coder/code-server/coder"
  version   = "1.6.0"
  agent_id  = coder_agent.main.id
  folder    = local.home_dir
  subdomain = false
  order     = 0
}

module "kiro" {
  source   = "registry.coder.com/coder/kiro/coder"
  version  = "1.2.2"
  agent_id = coder_agent.main.id
  order    = 1
}

module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  order    = 3

  # Installs the system packages the Kiro CLI and Kiro Crew installers need
  # before the module's install script runs.
  pre_install_script = file("${path.module}/kiro-crew-prereqs.sh")
}

# Terminal app for interactive Kiro CLI sign-in (`kiro-cli login`).
resource "coder_app" "kiro_cli" {
  agent_id     = coder_agent.main.id
  slug         = "kiro-cli"
  display_name = "Kiro CLI"
  icon         = "/icon/kiro.svg"
  command      = "kiro-cli"
  share        = "owner"
  order        = 2
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.35"
  agent_id = coder_agent.main.id
}

module "git-clone" {
  count    = data.coder_parameter.git_repo.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
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
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count            = data.coder_workspace.me.start_count
  depends_on       = [kubernetes_persistent_volume_claim_v1.home]
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
          run_as_user = 1000
          fs_group    = 1000
        }
        service_account_name = var.service_account_name != "" ? var.service_account_name : null

        container {
          name              = "dev"
          image             = var.image
          image_pull_policy = "IfNotPresent"
          command           = ["sh", "-c", coder_agent.main.init_script]
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
            mount_path = local.home_dir
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
            read_only  = false
          }
        }

        affinity {
          # Spread workspaces across nodes when possible.
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
