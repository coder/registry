---
name: coder-templates
description: Creates and updates Coder Registry workspace templates with agent setup, infrastructure provisioning, and module consumption
---

# Coder Templates

Coder workspace templates are complete workspace definitions that live under `registry/<namespace>/templates/<name>/` and provision the infrastructure that workspaces run on.

## Before You Start

Before writing or modifying any code:

1. **Understand the request.** What platform is the template targeting (Docker, AWS, GCP, Azure, Kubernetes)? What kind of workspace (VM, container, devcontainer)?
2. **Research existing templates and modules.** Search the registry for similar templates. Read their `main.tf` to understand patterns for that platform, especially how they handle agent setup, persistent storage, and module consumption. Also search for platform-specific helper modules (e.g. region selectors) that provide ready-made `coder_parameter` blocks; prefer these over hard-coding option lists.
3. **Check provider docs.** Verify the infrastructure provider resources you plan to use. Check both the Coder provider and the platform provider (AWS, Docker, etc.) version-specific docs if needed.
4. **Clarify before building.** If the request is ambiguous (e.g. unclear platform, whether to use devcontainers vs plain VMs, what parameters to expose, or which namespace to use), ask for clarification rather than guessing. Never assume a namespace; always confirm with the user.
5. **Plan the structure.** Decide on infrastructure resources, what `coder_parameter` options to expose, which registry modules to consume, and whether additional files like cloud-init configs are needed. When the user describes requirements in terms of their development needs rather than specific Terraform changes (e.g. "I need Node 20 + Postgres 16" or "make this template work for data science"), summarize what you plan to add or change before proceeding. Keep it brief: list the parameters, modules, and infrastructure changes. Skip this for straightforward requests where the action is clear (e.g. "add the code-server module" or "change the default region to us-west-2").

When updating an existing template, read and understand all of its current resources, parameters, and module consumption before making changes. If you observe patterns that deviate from the coder template standards (e.g. missing metadata blocks, hardcoded values that should be parameters, inline implementations that existing modules could replace, missing error handling in scripts), note these to the user as improvement opportunities in your response.

Features marked as "Premium" in this skill require a Coder Premium license. When your implementation uses a Premium feature, note this in your response to the user so they can verify their deployment supports it.

## Documentation References

### Coder

- Platform docs (latest): <https://coder.com/docs>
- Version-specific docs: `https://coder.com/docs/@v{MAJOR}.{MINOR}.{PATCH}` (e.g. <https://coder.com/docs/@v2.31.5>)
- Creating templates: <https://coder.com/docs/admin/templates/creating-templates>
- Extending templates: <https://coder.com/docs/admin/templates/extending-templates>
- Template parameters: <https://coder.com/docs/admin/templates/extending-templates/parameters>
- Workspace presets: <https://coder.com/docs/admin/templates/extending-templates/parameters#workspace-presets>
- Prebuilt workspaces: <https://coder.com/docs/admin/templates/extending-templates/prebuilt-workspaces>
- Tasks: <https://coder.com/docs/ai-coder/tasks>
- Agent Boundaries: <https://coder.com/docs/ai-coder/agent-boundaries>
- Coder Registry: <https://registry.coder.com>

### Coder Terraform provider

- Provider docs (latest): <https://registry.terraform.io/providers/coder/coder/latest/docs>
- Version-specific provider docs: replace `latest` with a version number (e.g. <https://registry.terraform.io/providers/coder/coder/2.13.1/docs>)

Resources:

| Resource         | Docs                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| `coder_agent`    | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent>    |
| `coder_app`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/app>      |
| `coder_script`   | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script>   |
| `coder_env`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/env>      |
| `coder_metadata` | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata> |
| `coder_ai_task`  | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/ai_task>  |

Data sources:

| Data Source              | Docs                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| `coder_parameter`        | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/parameter>        |
| `coder_workspace`        | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace>        |
| `coder_workspace_owner`  | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace_owner>  |
| `coder_provisioner`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/provisioner>      |
| `coder_workspace_preset` | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace_preset> |
| `coder_task`             | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/task>             |

### Terraform providers commonly used in templates

All provider docs follow `https://registry.terraform.io/providers/ORG/NAME/latest/docs`:

| Provider   | Source                 |
| ---------- | ---------------------- |
| Docker     | `kreuzwerker/docker`   |
| AWS        | `hashicorp/aws`        |
| Azure      | `hashicorp/azurerm`    |
| GCP        | `hashicorp/google`     |
| Kubernetes | `hashicorp/kubernetes` |

Browse all providers: <https://registry.terraform.io/browse/providers>

## Scaffolding a New Template

Only use this when creating a brand new template that does not yet exist. When updating an existing template, edit its files directly.

From repo root:

```bash
./scripts/new_template.sh namespace/template-name
```

Creates `registry/<namespace>/templates/<template-name>/` with:

- `main.tf`: full workspace Terraform config
- `README.md`: frontmatter and documentation

If the namespace is new, the script also creates `registry/<namespace>/` with a README. New namespaces additionally need:

- `registry/<namespace>/.images/avatar.png` (or `.svg`): square image, 400x400px minimum
- The namespace README `avatar` field pointing to `./.images/avatar.png`

The generated namespace README contains placeholder fields (name, links, avatar) that the user must fill out. After completing the template, inform the user that the namespace README needs to be updated with their information.

## main.tf

Templates define the full workspace stack: providers, agent, infrastructure resources, and module consumption.

```tf
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

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "memory"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
```

Key patterns:

- Provider version constraints must reflect actual functionality requirements. Only set a minimum `coder` provider version when the template uses a resource, attribute, or behavior introduced in that version. The same applies to infrastructure providers (Docker, AWS, etc.); check provider changelogs to confirm.
- Always include `data.coder_provisioner.me`, `data.coder_workspace.me`, `data.coder_workspace_owner.me`
- Use `data "coder_parameter"` for UI-facing options. When creating a new template, include parameters for the standard configurable options for that platform (e.g. region, CPU, memory, disk size for cloud/VM templates). Use existing templates for the same platform if they exist as a reference for which parameters to include and what defaults to set.
- Use `locals {}` for computed values: username, environment variables, startup scripts, URL assembly
- Use `data.coder_workspace.me.start_count` as `count` on ephemeral resources
- Connect containers/VMs to the agent via `coder_agent.main.init_script` and `CODER_AGENT_TOKEN`
- Add `metadata` blocks for workspace dashboard stats (`coder stat cpu`, `coder stat mem`, etc.)
- Optionally use `display_apps` block to hide specific built-in apps (defaults show all)
- Always search the registry at <https://registry.coder.com> before implementing any functionality from scratch. If a module already exists for what you need (region selectors, IDE integrations, developer tools, etc.), consume it rather than reimplementing it. When multiple modules serve similar purposes, prefer the actively maintained one and check that you are not using a deprecated or superseded module.
- Before consuming a module, verify its accepted variables. If you are inside the registry repo, read the module's `main.tf` directly (e.g. `registry/coder/modules/code-server/main.tf`). Otherwise, read the module's page at `https://registry.coder.com/modules/<namespace>/<module-name>` which includes the full source and variable definitions. Never pass arguments to a module without confirming they exist.
- Do not add comments that narrate what the code does or label sections. Only comment when explaining something non-obvious (e.g. why a workaround exists, a subtle constraint, or an unusual design choice).
- Label infrastructure resources with `coder.owner` and `coder.workspace_id` for tracking orphans
- Use `lifecycle { ignore_changes = all }` on persistent volumes to prevent data loss

### Additional files

Templates can include files beyond `main.tf` + `README.md`:

- `cloud-init/*.tftpl`: cloud-init configs for VM provisioning (AWS, Azure, GCP), loaded via `templatefile()`
- `build/Dockerfile`: custom container images built by the template
- `.tftpl` files: any Terraform template files for scripts, configs, or cloud-init data

### Presets

Workspace presets bundle commonly-used parameter combinations into selectable options. When a user creates a workspace, they can pick a preset to auto-fill multiple parameters at once. Define presets with `data "coder_workspace_preset"`:

```tf
data "coder_workspace_preset" "default" {
  name    = "Standard Dev Environment"
  default = true

  parameters = {
    "region"          = "us-east-1"
    "cpu"             = "4"
    "memory"          = "8"
    "container_image" = "codercom/enterprise-base:ubuntu"
  }
}
```

- The keys in `parameters` must match the `name` attribute of `coder_parameter` data sources in the same template.
- Set `default = true` on at most one preset to pre-select it in the UI.
- A template can define multiple presets for different use cases.
- Optional fields: `description` (context text in UI) and `icon` (e.g. `/emojis/1f680.png`).

### Prebuilds (Premium)

Prebuilds maintain an automatically-managed pool of pre-provisioned workspaces for a preset, reducing workspace creation time. This is a Premium feature. Prebuilds are configured as a nested block inside a preset:

```tf
data "coder_workspace_preset" "goland" {
  name = "GoLand: Large"
  parameters = {
    "jetbrains_ide" = "GO"
    "cpu"           = "8"
    "memory"        = "16"
  }

  prebuilds {
    instances = 3

    expiration_policy {
      ttl = 86400
    }

    scheduling {
      timezone = "UTC"
      schedule {
        cron      = "* 8-18 * * 1-5"
        instances = 5
      }
    }
  }
}
```

- `instances`: number of prebuilt workspaces to keep in the pool (base count when no schedule matches).
- `expiration_policy.ttl`: seconds before unclaimed prebuilds are cleaned up.
- `scheduling`: scale the pool up or down on a time-based cron schedule. The `cron` minute field must always be `*`.
- The preset must define all required parameters needed to build the workspace.
- When a prebuild is claimed, ownership transfers to the real user. Use `lifecycle { ignore_changes = [...] }` on resources that reference owner-specific values to prevent unnecessary recreation.

### Task-Oriented Templates

A template becomes task-capable by adding a `coder_ai_task` resource, which enables the Coder Tasks UI for AI agent workflows. Task templates require three additions on top of a regular template:

```tf
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.claude-code[count.index].task_app_id
}

data "coder_task" "me" {}

module "claude-code" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/claude-code/coder"
  version         = "~> 4.0"
  agent_id        = coder_agent.main.id
  workdir         = "/home/coder/projects"
  ai_prompt       = data.coder_task.me.prompt
  system_prompt   = data.coder_parameter.system_prompt.value
  model           = "sonnet"
  permission_mode = "plan"
  enable_boundary = true
}
```

- `coder_ai_task`: declares the template as task-capable. Its `app_id` must point to the agent module's `task_app_id` output.
- `data "coder_task"`: reads the user's task prompt. Pass it to the agent module via `ai_prompt`.
- Agent module: consume an AI agent module (`claude-code`, `codex`, etc.) with task-specific variables. Key variables include `ai_prompt`, `system_prompt`, `permission_mode`, and `enable_boundary`.
- Boundaries: set `enable_boundary = true` on the agent module to enable network-level filtering for the AI agent. See <https://coder.com/docs/ai-coder/agent-boundaries> for allowlist configuration.
- A `coder_app` with `slug = "preview"` gets special treatment in the Tasks UI navbar.
- Task templates heavily use presets to define scenarios (different repos, system prompts, setup scripts, container images).
- See `registry/coder-labs/templates/tasks-docker` as a reference implementation.

Docs: <https://coder.com/docs/ai-coder/tasks>

## README.md

Required YAML frontmatter:

```yaml
---
display_name: Docker Containers
description: Provision Docker containers with persistent home volumes as Coder workspaces
icon: ../../../../.icons/docker.svg
verified: false
tags: [docker, container]
---
```

Content rules:

- Single H1 heading matching `display_name`, directly below frontmatter
- When increasing header levels, increment by one each time (h1 -> h2 -> h3, not h1 -> h3)
- Opening paragraph describing what the template provisions. Be specific about the platform, compute type, and key capabilities (e.g. "Provision Kubernetes pods on an existing Amazon EKS cluster as Coder workspaces with persistent home volumes") rather than generic (e.g. "AWS Kubernetes template"). The frontmatter `description` field should follow the same principle.
- **Prerequisites** section (infrastructure requirements, provider credentials)
- **Architecture** section (what resources are created, what's ephemeral vs persistent)
- **Customization** section (how to modify startup scripts, add software, configure providers)
- Code fences labeled `tf` (NOT `hcl`)
- Relative icon paths (e.g. `../../../../.icons/`)
- **Do NOT include tables or lists that enumerate variables, parameters, or outputs.** The registry generates variable and output documentation automatically from the Terraform source. Workspace parameter options are visible in the Coder UI. Describe what the template does and how to use it in prose, not by listing every configurable field.
- Use [GFM alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts) for callouts: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`

## Icons

Templates reference icons in the README frontmatter `icon:` field using a relative path to the repo's `.icons/` directory (e.g. `../../../../.icons/aws.svg`). This icon is displayed on the registry website.

Workflow:

1. **Check what exists.** List the `.icons/` directory at the repo root for available SVGs.
2. **Use existing icons when they fit.** Most templates use a platform icon (aws, gcp, azure, docker, kubernetes) that already exists.
3. **When an icon doesn't exist,** reference the expected path anyway so the structure is correct. Try to source the official SVG from the platform's branding page or repository. If you can obtain it, add it to `.icons/` in this repo.
4. **Don't substitute a generic icon.** If the platform has its own brand identity, use the correct name even if the file doesn't exist yet.
5. **Notify the user.** After completing the template, inform the user in your response if any icons were referenced but not found. Note that missing icons need to be sourced and added to both this repo's `.icons/` directory and the `coder/coder` repo at `site/static/icon/`.

## Testing

Templates do NOT require `.tftest.hcl` or `main.test.ts`. Testing is done by pushing the template to a Coder deployment with `coder templates push`.

## Commands

| Task       | Command                           | Scope |
| ---------- | --------------------------------- | ----- |
| Format all | `bun run fmt`                     | Repo  |
| Validate   | `./scripts/terraform_validate.sh` | Repo  |

## Final Checks

Before considering the work complete, verify:

- README documents prerequisites and architecture
- Shell scripts handle errors gracefully (`|| echo "Warning..."` for non-fatal failures)
- No hardcoded values that should be configurable via variables or parameters
- No absolute URLs (use relative paths)
- `bun run fmt` has been run
