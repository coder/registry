---
display_name: Claude Code
description: Run the Claude Code agent in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, tasks, anthropic, aibridge]
---

# Claude Code

Run the [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) agent in your workspace to generate code and perform tasks. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "claude-code" {
  source         = "registry.coder.com/coder/claude-code/coder"
  version        = "4.5.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder/project"
  claude_api_key = "xxxx-xxxxx-xxxx"
}
```

> [!WARNING]
> **Security Notice**: This module uses the `--dangerously-skip-permissions` flag when running Claude Code tasks. This flag bypasses standard permission checks and allows Claude Code broader access to your system than normally permitted. While this enables more functionality, it also means Claude Code can potentially execute commands with the same privileges as the user running it. Use this module _only_ in trusted environments and be aware of the security implications.

> [!NOTE]
> By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

## Prerequisites

- An **Anthropic API key** or a _Claude Session Token_ is required for tasks.
  - You can get the API key from the [Anthropic Console](https://console.anthropic.com/dashboard).
  - You can get the Session Token using the `claude setup-token` command. This is a long-lived authentication token (requires Claude subscription)

### Session Resumption Behavior

By default, Claude Code automatically resumes existing conversations when your workspace restarts. Sessions are tracked per workspace directory, so conversations continue where you left off. If no session exists (first start), your `ai_prompt` will run normally. To disable this behavior and always start fresh, set `continue = false`

## Examples

### Usage with Agent Boundaries

This example shows how to configure the Claude Code module to run the agent behind a process-level boundary that restricts its network access.

```tf
module "claude-code" {
  source           = "registry.coder.com/coder/claude-code/coder"
  version          = "4.5.0"
  agent_id         = coder_agent.main.id
  workdir          = "/home/coder/project"
  enable_boundary  = true
  boundary_version = "v0.5.1"
}
```

### Usage with AI Bridge

[AI Bridge](https://coder.com/docs/ai-coder/ai-bridge) is a Premium Coder feature that provides centralized LLM proxy management. To use AI Bridge, set `enable_aibridge = true`.

For tasks integration with AI Bridge, add `enable_aibridge = true` to the [Usage with Tasks](#usage-with-tasks) example below.

#### Standalone usage with AI Bridge

```tf
module "claude-code" {
  source          = "registry.coder.com/coder/claude-code/coder"
  version         = "4.5.0"
  agent_id        = coder_agent.main.id
  workdir         = "/home/coder/project"
  enable_aibridge = true
}
```

When `enable_aibridge = true`, the module automatically sets:

- `ANTHROPIC_BASE_URL` to `${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic`
- `ANTHROPIC_AUTH_TOKEN` to the workspace owner's session token

This allows Claude Code to route API requests through Coder's AI Bridge instead of directly to Anthropic's API.
Template build will fail if either `claude_api_key` or `claude_code_oauth_token` is provided alongside `enable_aibridge = true`.

### Usage with Tasks

This example shows how to configure Claude Code with Coder tasks.

```tf
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.claude-code.task_app_id
}

data "coder_task" "me" {}

module "claude-code" {
  source         = "registry.coder.com/coder/claude-code/coder"
  version        = "4.5.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder/project"
  claude_api_key = "xxxx-xxxxx-xxxx"
  ai_prompt      = data.coder_task.me.prompt

  # Optional: route through AI Bridge (Premium feature)
  # enable_aibridge = true
}
```

### Advanced Configuration

This example shows additional configuration options for version pinning, custom models, and MCP servers.

> [!NOTE]
> When a specific `claude_code_version` (other than "latest") is provided, the module will install Claude Code via npm instead of the official installer. This allows for version pinning. The `claude_binary_path` variable can be used to specify where a pre-installed Claude binary is located.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "4.5.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"

  claude_api_key = "xxxx-xxxxx-xxxx"
  # OR
  claude_code_oauth_token = "xxxxx-xxxx-xxxx"

  claude_code_version = "2.0.62"          # Pin to a specific version (uses npm)
  claude_binary_path  = "/opt/claude/bin" # Path to pre-installed Claude binary
  agentapi_version    = "0.11.4"

  model           = "sonnet"
  permission_mode = "plan"

  mcp = <<-EOF
  {
    "mcpServers": {
      "my-custom-tool": {
        "command": "my-tool-server",
        "args": ["--port", "8080"]
      }
    }
  }
  EOF
}
```

### Standalone Mode

Run and configure Claude Code as a standalone CLI in your workspace.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "4.5.0"
  agent_id            = coder_agent.main.id
  workdir             = "/home/coder/project"
  install_claude_code = true
  claude_code_version = "2.0.62"
  report_tasks        = false
}
```

### Usage with Claude Code Subscription

```tf

variable "claude_code_oauth_token" {
  type        = string
  description = "Generate one using `claude setup-token` command"
  sensitive   = true
  value       = "xxxx-xxx-xxxx"
}

module "claude-code" {
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "4.5.0"
  agent_id                = coder_agent.main.id
  workdir                 = "/home/coder/project"
  claude_code_oauth_token = var.claude_code_oauth_token
}
```

### Usage with AWS Bedrock

#### Prerequisites

AWS account with Bedrock access, Claude models enabled in Bedrock console, appropriate IAM permissions.

Configure Claude Code to use AWS Bedrock for accessing Claude models through your AWS infrastructure.

```tf
resource "coder_env" "bedrock_use" {
  agent_id = coder_agent.main.id
  name     = "CLAUDE_CODE_USE_BEDROCK"
  value    = "1"
}

resource "coder_env" "aws_region" {
  agent_id = coder_agent.main.id
  name     = "AWS_REGION"
  value    = "us-east-1" # Choose your preferred region
}

# Option 1: Using AWS credentials

variable "aws_access_key_id" {
  type        = string
  description = "Your AWS access key ID. Create this in the AWS IAM console under 'Security credentials'."
  sensitive   = true
  value       = "xxxx-xxx-xxxx"
}

variable "aws_secret_access_key" {
  type        = string
  description = "Your AWS secret access key. This is shown once when you create an access key in the AWS IAM console."
  sensitive   = true
  value       = "xxxx-xxx-xxxx"
}

resource "coder_env" "aws_access_key_id" {
  agent_id = coder_agent.main.id
  name     = "AWS_ACCESS_KEY_ID"
  value    = var.aws_access_key_id
}

resource "coder_env" "aws_secret_access_key" {
  agent_id = coder_agent.main.id
  name     = "AWS_SECRET_ACCESS_KEY"
  value    = var.aws_secret_access_key
}

# Option 2: Using Bedrock API key (simpler)

variable "aws_bearer_token_bedrock" {
  type        = string
  description = "Your AWS Bedrock bearer token. This provides access to Bedrock without needing separate access key and secret key."
  sensitive   = true
  value       = "xxxx-xxx-xxxx"
}

resource "coder_env" "bedrock_api_key" {
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "4.5.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
  model    = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
```

> [!NOTE]
> For additional Bedrock configuration options (model selection, token limits, region overrides, etc.), see the [Claude Code Bedrock documentation](https://docs.claude.com/en/docs/claude-code/amazon-bedrock).

### Usage with Google Vertex AI

#### Prerequisites

GCP project with Vertex AI API enabled, Claude models enabled through Model Garden, service account with Vertex AI permissions, appropriate IAM permissions (Vertex AI User role).

Configure Claude Code to use Google Vertex AI for accessing Claude models through Google Cloud Platform.

```tf
variable "vertex_sa_json" {
  type        = string
  description = "The complete JSON content of your Google Cloud service account key file. Create a service account in the GCP Console under 'IAM & Admin > Service Accounts', then create and download a JSON key. Copy the entire JSON content into this variable."
  sensitive   = true
}

resource "coder_env" "vertex_use" {
  agent_id = coder_agent.main.id
  name     = "CLAUDE_CODE_USE_VERTEX"
  value    = "1"
}

resource "coder_env" "vertex_project_id" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_VERTEX_PROJECT_ID"
  value    = "your-gcp-project-id"
}

resource "coder_env" "cloud_ml_region" {
  agent_id = coder_agent.main.id
  name     = "CLOUD_ML_REGION"
  value    = "global"
}

resource "coder_env" "vertex_sa_json" {
  agent_id = coder_agent.main.id
  name     = "VERTEX_SA_JSON"
  value    = var.vertex_sa_json
}

resource "coder_env" "google_application_credentials" {
  agent_id = coder_agent.main.id
  name     = "GOOGLE_APPLICATION_CREDENTIALS"
  value    = "/tmp/gcp-sa.json"
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "4.5.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
  model    = "claude-sonnet-4@20250514"

  pre_install_script = <<-EOT
    #!/bin/bash
    # Write the service account JSON to a file
    echo "$VERTEX_SA_JSON" > /tmp/gcp-sa.json

    # Install prerequisite packages
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

    # Add Google Cloud public key
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

    # Add Google Cloud SDK repo to apt sources
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

    # Update and install the Google Cloud SDK
    sudo apt-get update && sudo apt-get install -y google-cloud-cli

    # Authenticate gcloud with the service account
    gcloud auth activate-service-account --key-file=/tmp/gcp-sa.json
  EOT
}
```

> [!NOTE]
> For additional Vertex AI configuration options (model selection, token limits, region overrides, etc.), see the [Claude Code Vertex AI documentation](https://docs.claude.com/en/docs/claude-code/google-vertex-ai).

## Troubleshooting

If you encounter any issues, check the log files in the `~/.claude-module` directory within your workspace for detailed information.

```bash
# Installation logs
cat ~/.claude-module/install.log

# Startup logs
cat ~/.claude-module/agentapi-start.log

# Pre/post install script logs
cat ~/.claude-module/pre_install.log
cat ~/.claude-module/post_install.log
```

> [!NOTE]
> To use tasks with Claude Code, you must provide an `anthropic_api_key` or `claude_code_oauth_token`.
> The `workdir` variable is required and specifies the directory where Claude Code will run.

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
