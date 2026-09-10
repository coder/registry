terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}
provider "docker" {}

variable "image" {
  description = <<-EOF
  Container image for the workspace. Must include the Coder CLI; the
  dogfood image ships coder, terraform, git, gh, the docker CLI, Node,
  Go, and Python out of the box.
  EOF
  type        = string
  default     = "codercom/oss-dogfood:latest"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  type         = "number"
  default      = "2"
  mutable      = true
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  type         = "number"
  default      = "4"
  mutable      = true
  validation {
    min = 1
    max = 64
  }
}

data "coder_parameter" "git_repo_url" {
  name         = "git_repo_url"
  display_name = "Git repository to clone (optional)"
  description  = "If set, cloned into ~/projects on first start. Leave blank to skip."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "install_registry_skills" {
  name         = "install_registry_skills"
  display_name = "Install coder/registry agent skills"
  description  = <<-EOT
    Clone coder/registry into ~/registry and symlink the coder-templates
    and coder-modules agent skills into ~/.claude/skills/ so agents
    (Claude Code, etc.) authoring registry content from this workspace
    pick them up automatically. Disable if you don't need them.
  EOT
  type         = "bool"
  default      = "true"
  mutable      = true
}

# ---------------------------------------------------------------------------
# Coder agent
# ---------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script_behavior = "blocking"

  env = {
    INSTALL_REGISTRY_SKILLS = data.coder_parameter.install_registry_skills.value
  }

  startup_script = <<-EOT
    set -eu
    mkdir -p "$HOME/projects"
    # Friendly banner on every new shell
    cat > "$HOME/.coder-welcome" <<'BANNER'
    ────────────────────────────────────────────────────────────────
     Coder CLI workspace (dogfood image)
    ────────────────────────────────────────────────────────────────
     You are auto-logged-in via the coder-login module.
       coder templates list
       coder templates push <name> --directory .
       coder workspaces list
       coder ssh <workspace>
    ────────────────────────────────────────────────────────────────
    BANNER
    if ! grep -q '.coder-welcome' "$HOME/.bashrc" 2>/dev/null; then
      echo 'cat $HOME/.coder-welcome 2>/dev/null || true' >> "$HOME/.bashrc"
    fi

    # ---- Install coder/registry agent skills ------------------------------
    # Clone coder/registry once and symlink the in-tree skills into
    # ~/.claude/skills/ so any agent in this workspace (Claude Code, etc.)
    # picks them up when authoring new templates or modules.
    if [ "$INSTALL_REGISTRY_SKILLS" = "true" ]; then
      if [ ! -d "$HOME/registry/.git" ]; then
        echo "[coder-cli] Cloning coder/registry for agent skills ..."
        git clone --depth=1 https://github.com/coder/registry.git "$HOME/registry" 2>&1 | tail -3 || true
      fi
      mkdir -p "$HOME/.claude/skills"
      for skill in coder-templates coder-modules; do
        src="$HOME/registry/.agents/skills/$skill"
        if [ -f "$src/SKILL.md" ]; then
          ln -sfn "$src" "$HOME/.claude/skills/$skill"
          echo "[coder-cli] linked agent skill: $skill"
        else
          echo "[coder-cli] WARNING: skill source missing at $src" >&2
        fi
      done
    fi
  EOT

  metadata {
    display_name = "CPU usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory usage"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Home disk"
    key          = "home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
  metadata {
    display_name = "Registry skills"
    key          = "registry_skills"
    script       = "ls $HOME/.claude/skills 2>/dev/null | tr '\\n' ' ' | sed 's/ $//' || echo 'none'"
    interval     = 60
    timeout      = 2
  }
}

# ---------------------------------------------------------------------------
# Registry modules
# ---------------------------------------------------------------------------

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count != 0 && data.coder_parameter.git_repo_url.value != "" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.3"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo_url.value
  base_dir = "/home/coder/projects"
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.5.2"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/projects"
}

# ---------------------------------------------------------------------------
# Docker volume + container
# ---------------------------------------------------------------------------

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

data "docker_registry_image" "workspace" {
  name = var.image
}

resource "docker_image" "workspace" {
  name          = var.image
  pull_triggers = [data.docker_registry_image.workspace.sha256_digest]
  keep_locally  = true
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.workspace.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
