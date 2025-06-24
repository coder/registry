# Coder Modules: Comprehensive Documentation

_Technical reference for understanding, developing, and implementing Coder modules in workspace environments_

## Table of Contents

1. [Foundation & Core Concepts](#foundation--core-concepts)
2. [How Coder Modules Work](#how-coder-modules-work)
3. [Module Architecture & Registry](#module-architecture--registry)
4. [Module Implementation Patterns](#module-implementation-patterns)
5. [Reference & Resources](#reference--resources)

---

## Foundation & Core Concepts

### What are Coder Modules?

Coder modules are reusable Terraform configurations that extend Coder workspaces with development tools, integrations, and functionality. Each module encapsulates a specific capability and can be integrated into workspace templates to provide targeted functionality.

Modules are building blocks that add functionality to Coder workspaces. Instead of manually configuring development tools, you include a module and it handles the setup automatically.

### Key Features

Modules provide several key features that make Coder workspaces powerful and scalable:

**Reusability**: Write once, use everywhere. Modules eliminate configuration duplication across multiple templates and environments.

**Consistency**: Standardized implementations ensure uniform development environments and enforce best practices across teams.

**Composability**: Mix and match modules to create comprehensive development environments tailored to specific needs.

**Maintainability**: Centralized module development means bug fixes and improvements benefit all users, with controlled updates ensuring stability and predictable change management.

**Speed**: Automated setup and configuration reduces manual overhead and accelerates development environment creation.

### Ecosystem Integration

Coder modules operate within a structured ecosystem:

- **Coder Platform**: Core infrastructure management and workspace orchestration
- **Templates**: Terraform configurations defining workspace infrastructure and module integration
- **Modules**: Reusable components providing specific functionality extensions
- **Registry**: Centralized repository for module discovery and distribution
- **Agents**: Runtime components executing module-defined operations within workspaces

The relationship between these components enables scalable workspace management:

```
                      ┌─────────────────────────┐
                      │     Coder Platform      │
                      │                         │
                      │   Orchestrates entire   │
                      │   workspace lifecycle   │
                      └───────────┬─────────────┘
                                  │
                                  │ Manages
                                  ▼
                      ┌─────────────────────────┐
                      │    Module Registry      │◄─── Publishes
                      │                         │     modules
                      │ Hosts and distributes   │
                      │    reusable modules     │
                      └───────────┬─────────────┘
                                  │
                                  │ Provides modules
                                  ▼
                      ┌─────────────────────────┐
                      │      Templates          │◄─── Users create
                      │                         │     templates
                      │ Define infrastructure   │
                      │ and integrate modules   │
                      └───────────┬─────────────┘
                                  │
                                  │ Provisions
                                  ▼
                      ┌─────────────────────────┐
                      │      Workspaces         │◄─── Developers use
                      │                         │     workspaces
                      │  Running development    │
                      │     environments        │
                      └─────────────────────────┘
```

### Terraform Foundation

Coder modules are implemented as Terraform modules using HashiCorp's infrastructure-as-code framework. The [Coder Terraform provider](https://registry.terraform.io/providers/coder/coder/latest/docs) extends standard Terraform functionality with workspace-specific resources:

**Core Module Resources:**

- [`coder_script`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script): Executes scripts during workspace lifecycle events
- [`coder_app`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/app): Creates accessible applications within the workspace interface
- [`coder_env`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/env): Sets environment variables in the workspace

**Template Resources (rarely used in modules):**

- [`coder_agent`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent): Defines agent configuration for workspace runtime
- [`coder_parameter`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/parameter): Collects user input during workspace provisioning
- [`coder_metadata`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata): Displays resource information in the workspace interface

**Advanced Resources:**

- [`coder_agent_instance`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent_instance): Manages agent instance connections
- [`coder_ai_task`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/ai_task): Defines AI-powered task automation
- [`coder_devcontainer`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/devcontainer): Configures development container environments

Modules use standard Terraform syntax plus these Coder-specific resources to integrate with workspaces.

### Provider and Terraform Requirements

Modules specify required Terraform and provider versions:

```tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}
```

This ensures compatibility with minimum versions of Terraform and the Coder provider.

**Current Version Standards:**

- **Latest Coder Provider**: v2.8.0 (June 2025)
- **Recommended Minimum**: `>= 2.5` (used by most current modules)
- **Legacy Modules**: Some older modules still use lower versions (0.12+) but should be updated when possible

New modules should use `>= 2.5` to ensure access to modern features like app groups, prebuilt workspaces, and improved validation.

---

## How Coder Modules Work

### Module Lifecycle

Module execution follows a defined lifecycle within workspace operations:

1. **Template Processing**: Templates reference modules and define configuration parameters
2. **Resource Planning**: Terraform analyzes module dependencies and resource requirements
3. **Resource Provisioning**: Terraform creates infrastructure and workspace resources
4. **Agent Initialization**: Coder agent starts and processes module-defined scripts
5. **Runtime Operation**: Modules provide ongoing functionality through applications and integrations

### Core Module Components

#### Input Variables

Modules define input variables to control behavior and configuration:

```tf
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "The port to run VS Code Web on."
  default     = 13338
}

variable "extensions" {
  type        = list(string)
  description = "A list of extensions to install."
  default     = []
}

variable "accept_license" {
  type        = bool
  description = "Accept the VS Code Server license. https://code.visualstudio.com/license/server"
  default     = false
  validation {
    condition     = var.accept_license == true
    error_message = "You must accept the VS Code license agreement by setting accept_license=true."
  }
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}
```

#### Variable Validation Patterns

Modules use validation blocks to catch configuration errors early:

```tf
# Example from jetbrains-gateway module
variable "arch" {
  type        = string
  description = "The target architecture of the workspace"
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "Architecture must be either 'amd64' or 'arm64'."
  }
}

variable "channel" {
  type        = string
  description = "JetBrains IDE release channel. Valid values are release and eap."
  default     = "release"
  validation {
    condition     = can(regex("^(release|eap)$", var.channel))
    error_message = "The channel must be either release or eap."
  }
}

variable "jetbrains_ides" {
  type        = list(string)
  description = "The list of IDE product codes."
  default     = ["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"]
  validation {
    condition = (
      alltrue([
        for code in var.jetbrains_ides : contains(["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"], code)
      ])
    )
    error_message = "The jetbrains_ides must be a list of valid product codes. Valid product codes are ${join(",", ["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"])}."
  }
}
```

#### Sensitive Variables

Modules handling credentials or API keys use sensitive variables:

```tf
# Example from aider module
variable "ai_api_key" {
  type        = string
  description = "API key for the selected AI provider."
  default     = ""
  sensitive   = true
}

# Example from windows-rdp module
variable "admin_password" {
  type      = string
  default   = "coderRDP!"
  sensitive = true
}
```

#### Multi-line Descriptions

Complex variable descriptions use heredoc syntax for better readability:

```tf
# Example from code-server module
variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = false
}

# Example from jfrog-oauth module
variable "package_managers" {
  type = object({
    npm    = optional(list(string), [])
    go     = optional(list(string), [])
    pypi   = optional(list(string), [])
    docker = optional(list(string), [])
  })
  description = <<-EOF
    A map of package manager names to their respective artifactory repositories. Unused package managers can be omitted.
    For example:
      {
        npm    = ["GLOBAL_NPM_REPO_KEY", "@SCOPED:NPM_REPO_KEY"]
        go     = ["YOUR_GO_REPO_KEY", "ANOTHER_GO_REPO_KEY"]
        pypi   = ["YOUR_PYPI_REPO_KEY", "ANOTHER_PYPI_REPO_KEY"]
        docker = ["YOUR_DOCKER_REPO_KEY", "ANOTHER_DOCKER_REPO_KEY"]
      }
  EOF
}
```

#### Resource Definitions

Modules create Coder-specific resources to implement functionality:

```tf
resource "coder_script" "vscode-web" {
  agent_id     = var.agent_id
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  script = templatefile("${path.module}/run.sh", {
    PORT : var.port,
    LOG_PATH : var.log_path,
    INSTALL_PREFIX : var.install_prefix,
    EXTENSIONS : join(",", var.extensions),
    TELEMETRY_LEVEL : var.telemetry_level,
    SETTINGS : replace(jsonencode(var.settings), "\"", "\\\""),
    FOLDER : var.folder,
    SERVER_BASE_PATH : local.server_base_path,
    COMMIT_ID : var.commit_id,
  })
  run_on_start = true
}

resource "coder_app" "vscode-web" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = local.url
  icon         = "/icon/code.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = local.healthcheck_url
    interval  = 5
    threshold = 6
  }
}
```

#### Lifecycle Preconditions

Advanced modules use lifecycle preconditions to validate configuration at the Terraform level:

```tf
# Example from code-server module
resource "coder_script" "code-server" {
  agent_id     = var.agent_id
  display_name = "code-server"
  script       = templatefile("${path.module}/run.sh", local.template_vars)
  run_on_start = true

  lifecycle {
    precondition {
      condition     = !var.offline || length(var.extensions) == 0
      error_message = "Offline mode does not allow extensions to be installed"
    }

    precondition {
      condition     = !var.offline || !var.use_cached
      error_message = "Offline and Use Cached can not be used together"
    }
  }
}
```

#### External App Resources

Some modules create links to external documentation or resources:

```tf
# Example from windows-rdp module
resource "coder_app" "rdp-docs" {
  agent_id     = var.agent_id
  display_name = "Local RDP Docs"
  slug         = "rdp-docs"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/windows.svg"
  url          = "https://coder.com/docs/ides/remote-desktops#rdp-desktop"
  external     = true
}
```

#### Output Values

Most modules don't need output values, but some specialized modules provide them for template integration and inter-module communication. Outputs are typically used by:

- **Region selector modules** (for passing selected regions to infrastructure)
- **Authentication modules** (for sharing tokens/credentials)
- **Git modules** (for sharing repository information)

```tf
# Example from git-clone module
output "repo_dir" {
  value       = local.clone_path
  description = "Full path of cloned repo directory"
}

output "clone_url" {
  value       = local.clone_url
  description = "The exact Git repository URL that will be cloned"
}

output "folder_name" {
  value       = local.folder_name
  description = "The name of the folder that will be created"
}

# Example from jetbrains-gateway module
output "identifier" {
  value = local.identifier
}

output "download_link" {
  value = local.download_link
}

output "url" {
  value = coder_app.gateway.url
}
```

### Module Integration with Templates

Modules are designed to integrate seamlessly with Coder templates, following established patterns for configuration and lifecycle management.

#### Parameter Collection

Most modules receive user input through variables passed from templates. Only specialized modules (like region selectors) collect parameters directly:

```tf
# Example from gcp-region module
data "coder_parameter" "region" {
  name         = "gcp_region"
  display_name = var.display_name
  description  = var.description
  icon         = "/icon/gcp.png"
  mutable      = var.mutable
  default      = var.default != null && var.default != "" && (!var.gpu_only || try(local.zones[var.default].gpu, false)) ? var.default : null
  order        = var.coder_parameter_order
  dynamic "option" {
    for_each = {
      for k, v in local.zones : k => v
      if anytrue([for d in var.regions : startswith(k, d)]) && (!var.gpu_only || v.gpu) && (!var.single_zone_per_region || endswith(k, "-a"))
    }
    content {
      icon        = try(var.custom_icons[option.key], option.value.icon)
      name        = try(var.custom_names[option.key], var.single_zone_per_region ? substr(option.value.name, 0, length(option.value.name) - 4) : option.value.name)
      description = option.key
      value       = option.key
    }
  }
}

# Template usage example
module "gcp_region" {
  source  = "registry.coder.com/coder/gcp-region/coder"
  default = "us-central1-a"
  regions = ["us-central1", "us-west1"]
}
```

**Best Practice**: Define parameters in templates and pass values to modules via variables, rather than having modules collect parameters directly.

#### Template Integration Patterns

Templates integrate modules using several established patterns:

**Conditional Loading**: Templates use `start_count` to conditionally load modules based on workspace state, ensuring modules only run when workspaces are active.

**Simple Composition**: Templates include multiple modules independently, each handling specific functionality without complex interdependencies.

**Parameter-Driven Configuration**: Templates collect user input via `coder_parameter` and pass values to modules through variables, keeping input collection separate from module implementation.

**Version Pinning**: Templates pin module versions using version constraints (e.g., `version = "~> 1.0"`) to ensure stability while allowing compatible updates.

### Advanced Module Capabilities

#### Common Data Sources

Most modules use standard data sources to access workspace context:

```tf
# Essential data sources for workspace context
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Architecture detection for platform-specific installations
data "coder_provisioner" "me" {}

# Example usage in modules
locals {
  # Platform-specific binary selection
  arch_suffix = data.coder_provisioner.me.arch == "arm64" ? "-arm64" : ""

  # Dynamic URL construction
  workspace_url = "https://${data.coder_workspace.me.access_url}"

  # User-specific configuration
  owner_name = data.coder_workspace_owner.me.name
}

# Example from jetbrains-gateway module - Architecture-based logic
locals {
  download_key = var.arch == "arm64" ? "linuxARM64" : "linux"

  # Complex architecture detection and IDE version handling
  effective_jetbrains_ide_versions = {
    for k, v in var.jetbrains_ide_versions : k => {
      build_number = v.build_number
      version      = var.arch == "arm64" ? "${v.version}-aarch64" : v.version
    }
  }
}
```

#### Conditional Logic

Modules can use conditional logic for various purposes including URL construction, resource configuration, and feature toggling:

```tf
# Example from vscode-web module
locals {
  server_base_path = var.subdomain ? "" : format("/@%s/%s/apps/%s/", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, var.slug)
  url              = var.folder == "" ? "http://localhost:${var.port}${local.server_base_path}" : "http://localhost:${var.port}${local.server_base_path}?folder=${var.folder}"
  healthcheck_url  = var.subdomain ? "http://localhost:${var.port}/healthz" : "http://localhost:${var.port}${local.server_base_path}/healthz"
}

# Example from jetbrains-gateway module  
locals {
  download_key = var.arch == "arm64" ? "linuxARM64" : "linux"
  effective_jetbrains_ide_versions = {
    for k, v in var.jetbrains_ide_versions : k => {
      build_number = v.build_number
      version      = var.arch == "arm64" ? "${v.version}-aarch64" : v.version
    }
  }
}
```

#### Complex Local Value Processing

Modules often use sophisticated local value processing for data transformation:

```tf
# Example from aider module - Environment variable mapping
locals {
  provider_env_vars = {
    openai    = "OPENAI_API_KEY"
    anthropic = "ANTHROPIC_API_KEY"
    azure     = "AZURE_OPENAI_API_KEY"
    google    = "GOOGLE_API_KEY"
    cohere    = "COHERE_API_KEY"
    mistral   = "MISTRAL_API_KEY"
    ollama    = "OLLAMA_HOST"
    custom    = var.custom_env_var_name
  }

  env_var_name = local.provider_env_vars[var.ai_provider]

  encoded_pre_install_script = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
}

# Example from jfrog-oauth module - Template processing
locals {
  npmrc = templatefile(
    "${path.module}/.npmrc.tftpl",
    merge(
      local.common_values,
      {
        REPOS = [
          for r in var.package_managers.npm :
          strcontains(r, ":") ? zipmap(["SCOPE", "NAME"], ["${split(":", r)[0]}:", split(":", r)[1]]) : { SCOPE = "", NAME = r }
        ]
      }
    )
  )
}
```

#### External Integrations

Modules can integrate with external services and APIs:

```tf
# Example from jfrog-oauth module
data "coder_external_auth" "jfrog" {
  id = var.external_auth_id
}

resource "coder_env" "jfrog_ide_access_token" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_ACCESS_TOKEN"
  value    = data.coder_external_auth.jfrog.access_token
}

resource "coder_env" "goproxy" {
  count    = length(var.package_managers.go) == 0 ? 0 : 1
  agent_id = var.agent_id
  name     = "GOPROXY"
  value = join(",", [
    for repo in var.package_managers.go :
    "https://${local.username}:${data.coder_external_auth.jfrog.access_token}@${local.jfrog_host}/artifactory/api/go/${repo}"
  ])
}
```

---

## Module Architecture & Registry

### Module Architecture

A Coder module implements a standard Terraform module structure with Coder-specific conventions:

```
module-name/
├── main.tf          # Primary Terraform configuration
├── README.md        # Documentation with structured frontmatter
├── main.test.ts     # Automated test suite
└── run.sh          # Optional execution script
```

### Module Registry and Namespaces

Modules in the Coder Registry are organized using namespaces, which provide a way to group modules by their maintainers and ensure unique module names across the ecosystem.

#### Understanding Namespaces

Each namespace represents a distinct contributor or organization:

- **`coder`**: The official namespace maintained by the Coder team. All modules in this namespace are verified and maintained with official support.
- **Community namespaces**: Individual contributors and organizations can create their own namespaces (e.g., `thezoker`, `whizus`, `nataindata`) to publish modules.

#### Module Source Format

When referencing a module in your template, use the following format:

```
registry.coder.com/[namespace]/[module-name]/coder
```

For example:

- Official module: `registry.coder.com/coder/vscode-web/coder`
- Community module: `registry.coder.com/thezoker/nodejs/coder`

The trailing `/coder` is a required constant that indicates this is a Coder-specific module.

#### Namespace Directory Structure

Within the registry repository, modules are organized as:

```
registry/
├── coder/           # Official namespace
│   └── modules/
│       ├── vscode-web/
│       ├── cursor/
│       └── ...
├── thezoker/        # Community namespace
│   └── modules/
│       └── nodejs/
└── whizus/          # Community namespace
    └── modules/
        ├── exoscale-zone/
        └── ...
```

#### Creating Your Own Namespace

To contribute modules under your own namespace:

1. Fork the registry repository
2. Create a directory with your GitHub username or organization name under `/registry/`
3. Add a `modules/` subdirectory for your modules
4. Each module gets its own directory containing the standard module files
5. Submit a pull request to have your modules included in the registry

#### Namespace Verification

- Modules in the `coder` namespace are automatically verified
- Verification status is indicated in the module's README frontmatter

---

## Module Implementation Patterns

Common patterns for building reliable Coder modules.

### Core Implementation Patterns

#### The Standard Module Structure

Standard structure for Coder modules:

```tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

# Required variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

# Optional variables with sensible defaults
variable "version" {
  type        = string
  description = "Version to install."
  default     = "latest"
}

# Data sources for workspace context
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Main functionality
resource "coder_script" "install" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/install.sh", {
    version = var.version
  })
}

resource "coder_app" "main" {
  count        = data.coder_workspace.me.start_count
  agent_id     = var.agent_id
  display_name = "Application"
  icon         = "/icon/app.svg"
  url          = "http://localhost:8080"
}

# Outputs for other modules or templates
output "app_url" {
  value       = try(coder_app.main[0].url, "")
  description = "The URL to access the application."
}
```

#### Conditional Resource Creation

Modules use conditional resource creation based on configuration variables:

```tf
# Example from jfrog-oauth module
resource "coder_env" "jfrog_ide_url" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_URL"
  value    = var.jfrog_url
}

resource "coder_env" "goproxy" {
  count    = length(var.package_managers.go) == 0 ? 0 : 1
  agent_id = var.agent_id
  name     = "GOPROXY"
  value = join(",", [
    for repo in var.package_managers.go :
    "https://${local.username}:${data.coder_external_auth.jfrog.access_token}@${local.jfrog_host}/artifactory/api/go/${repo}"
  ])
}

# Example from vscode-desktop module
resource "coder_app" "vscode" {
  agent_id     = var.agent_id
  external     = true
  icon         = "/icon/code.svg"
  slug         = "vscode"
  display_name = "VS Code Desktop"
  order        = var.order
  group        = var.group

  url = join("", [
    "vscode://coder.coder-remote/open",
    "?owner=",
    data.coder_workspace_owner.me.name,
    "&workspace=",
    data.coder_workspace.me.name,
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])
}
```

### Advanced Implementation Patterns

#### Complex Installation Pattern

Complex modules handle multi-step installation within a single script:

```tf
resource "coder_script" "install" {
  agent_id     = var.agent_id
  display_name = "Install Application"
  script = templatefile("${path.module}/install.sh", {
    version      = var.version
    arch         = data.coder_provisioner.me.arch
    workspace_id = data.coder_workspace.me.id
    folder       = var.folder
  })
  run_on_start = true
}
```

#### Service Installation Pattern

Modules typically install and configure services during workspace startup:

```tf
resource "coder_script" "install_service" {
  agent_id     = var.agent_id
  display_name = "Install Service"
  script       = file("${path.module}/install.sh")
  run_on_start = true
}

resource "coder_app" "service" {
  agent_id     = var.agent_id
  slug         = "service"
  display_name = "Service"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/service.svg"
  subdomain    = true

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 6
  }
}
```

#### Configuration Template Pattern

Modules often need to generate configuration files:

```tf
resource "coder_script" "generate_config" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/generate-config.sh", {
    config_content = templatefile("${path.module}/config.tpl", {
      workspace_name  = data.coder_workspace.me.name
      owner_email     = data.coder_workspace_owner.me.email
      custom_settings = var.custom_settings
    })
  })
}
```

#### External Service Integration Pattern

Modules that integrate with external services use external authentication:

```tf
variable "external_auth_id" {
  type        = string
  description = "External auth ID for the service."
  default     = "github"
}

data "coder_external_auth" "service" {
  id = var.external_auth_id
}

resource "coder_script" "setup_integration" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/setup.sh", {
    auth_token  = data.coder_external_auth.service.access_token
    service_url = var.service_url
    external_id = data.coder_external_auth.service.id
  })
  run_on_start = true
}
```

### User Experience Patterns

#### Simple Configuration

Modules provide sensible defaults to minimize required configuration:

```tf
variable "port" {
  type        = number
  description = "Port number for the application."
  default     = 8080
}

variable "extensions" {
  type        = list(string)
  description = "List of extensions to install."
  default     = []
}

# Most configuration is optional with good defaults
resource "coder_app" "main" {
  agent_id     = var.agent_id
  slug         = "app"
  display_name = "Application"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/app.svg"
  subdomain    = true
}
```

#### Accepting Template Parameters

Modules typically receive user preferences through variables passed from templates:

```tf
variable "theme" {
  type        = string
  description = "UI theme to use."
  default     = "dark"
  validation {
    condition     = contains(["dark", "light", "auto"], var.theme)
    error_message = "Theme must be dark, light, or auto."
  }
}

variable "extensions" {
  type        = list(string)
  description = "List of extensions to install."
  default     = ["git", "docker"]
}

# Use the template-provided values
resource "coder_script" "configure_theme" {
  agent_id = var.agent_id
  script   = "configure_app --theme=${var.theme}"
}
```

Templates handle user input, modules handle implementation.

### Error Handling and Resilience Patterns

#### Application Health Checks

Modules typically include health checks for web applications:

```tf
# Example from vscode-web module
resource "coder_app" "vscode-web" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = local.url
  icon         = "/icon/code.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = local.healthcheck_url
    interval  = 5
    threshold = 6
  }
}

# Example from windows-rdp module
resource "coder_app" "windows-rdp" {
  agent_id     = var.agent_id
  share        = var.share
  slug         = "web-rdp"
  display_name = "Web RDP"
  url          = "http://localhost:7171"
  icon         = "/icon/desktop.svg"
  subdomain    = true
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:7171"
    interval  = 5
    threshold = 15
  }
}
```

---

## Reference & Resources

Quick reference for module development and usage.

### Quick Reference Guide

#### Essential Module Structure

Every Coder module follows this basic structure:

```
module-name/
├── main.tf          # Core Terraform configuration
├── README.md        # Documentation with frontmatter
├── main.test.ts     # Test suite (required)
├── run.sh          # Optional execution script
└── assets/         # Optional additional files
    ├── scripts/
    ├── configs/
    └── templates/
```

#### Required Frontmatter Format

All module READMEs must include proper frontmatter:

```yaml
---
display_name: Module Display Name
description: Brief description of module functionality
icon: ../../../../.icons/module-icon.svg
maintainer_github: github-username
verified: false # true for official modules
tags: [tag1, tag2, tag3]
---
```

#### Common Module Patterns

**Basic Module Template:**

```tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "The port to run JupyterLab on."
  default     = 19999
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_script" "jupyterlab" {
  agent_id     = var.agent_id
  display_name = "jupyterlab"
  icon         = "/icon/jupyter.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port
    BASE_URL : var.subdomain ? "" : "/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}/apps/jupyterlab"
  })
  run_on_start = true
}

resource "coder_app" "jupyterlab" {
  agent_id     = var.agent_id
  slug         = "jupyterlab"
  display_name = "JupyterLab"
  url          = var.subdomain ? "http://localhost:${var.port}" : "http://localhost:${var.port}/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}/apps/jupyterlab"
  icon         = "/icon/jupyter.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
}
```

### Development Resources

#### Testing Framework

The registry uses Bun for testing with specific patterns:

```typescript
import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("module-name", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("creates expected resources", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });

    // Test assertions
    expect(state.resources).toBeDefined();
  });
});
```

#### Validation Tools

Use the built-in validation tools:

```bash
# Format code
bun run fmt

# Validate Terraform
bun run terraform-validate

# Run tests
bun test

# Test specific module
bun test -t "module-name"
```

#### Documentation Standards

Documentation requirements:

- Write clear descriptions and examples
- Use consistent formatting
- Keep docs updated with code changes
- Explain why, not just what

### Module Registry Resources

#### Official Registry

- **Registry Website**: [https://registry.coder.com](https://registry.coder.com)
- **GitHub Repository**: [https://github.com/coder/registry](https://github.com/coder/registry)
- **Contributing Guide**: [CONTRIBUTING.md](https://github.com/coder/registry/blob/main/CONTRIBUTING.md)

#### Coder Documentation

- **Terraform Modules Guide**: [https://coder.com/docs/admin/templates/extending-templates/modules](https://coder.com/docs/admin/templates/extending-templates/modules)
- **Template Creation**: [https://coder.com/docs/tutorials/template-from-scratch](https://coder.com/docs/tutorials/template-from-scratch)
- **Coder Provider Documentation**: Available in the Terraform Registry

#### Community Resources

- **Discord Community**: [https://discord.gg/coder](https://discord.gg/coder)
- **GitHub Discussions**: Repository discussions for questions and ideas
- **Community Examples**: Template examples in the main Coder repository

### Module Versioning

#### Semantic Versioning

Modules follow semantic versioning (MAJOR.MINOR.PATCH):

- **Patch** (1.2.3 → 1.2.4): Bug fixes that don't affect the API
- **Minor** (1.2.3 → 1.3.0): New features, backward-compatible changes
- **Major** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing types)

#### Version Bumping

When modifying a module, use the version bump script:

```bash
# For bug fixes
./.github/scripts/version-bump.sh patch

# For new features
./.github/scripts/version-bump.sh minor

# For breaking changes
./.github/scripts/version-bump.sh major
```

The script automatically detects changed modules, calculates new version numbers, and updates README files.

---

_This document represents the current state of Coder modules and will continue to evolve as the ecosystem grows. For the most up-to-date information, always refer to the official Coder documentation and registry._

**Version**: 1.0  
**Last Updated**: June 2025  
**Maintained by**: Coder Team