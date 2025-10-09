---
display_name: Claude Code
description: Run the Claude Code agent in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, tasks, anthropic]
---

# Claude Code

Run the [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) agent in your workspace to generate code and perform tasks. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "claude-code" {
  source         = "registry.coder.com/coder/claude-code/coder"
  version        = "3.1.1"
  agent_id       = coder_agent.example.id
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

## Examples

### Usage with Tasks and Advanced Configuration

This example shows how to configure the Claude Code module with an AI prompt, API key shared by all users of the template, and other custom settings.

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial task prompt for Claude Code."
  mutable     = true
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "3.1.1"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  claude_api_key = "xxxx-xxxxx-xxxx"
  # OR
  claude_code_oauth_token = "xxxxx-xxxx-xxxx"

  claude_code_version = "1.0.82" # Pin to a specific version
  agentapi_version    = "v0.10.0"

  ai_prompt = data.coder_parameter.ai_prompt.value
  model     = "sonnet"

  permission_mode = "plan"

  mcp = <<-EOF
  {
    "mcpServers": {
      "my-custom-tool": {
        "command": "my-tool-server"
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
  version             = "3.1.1"
  agent_id            = coder_agent.example.id
  workdir             = "/home/coder"
  install_claude_code = true
  claude_code_version = "latest"
  report_tasks        = false
  cli_app             = true
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
  version                 = "3.1.1"
  agent_id                = coder_agent.example.id
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
  agent_id = coder_agent.example.id
  name     = "CLAUDE_CODE_USE_BEDROCK"
  value    = "1"
}

resource "coder_env" "aws_region" {
  agent_id = coder_agent.example.id
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
  agent_id = coder_agent.example.id
  name     = "AWS_ACCESS_KEY_ID"
  value    = var.aws_access_key_id
}

resource "coder_env" "aws_secret_access_key" {
  agent_id  = coder_agent.example.id
  name      = "AWS_SECRET_ACCESS_KEY"
  value     = var.aws_secret_access_key"
}

# Option 2: Using Bedrock API key (simpler)

variable "aws_bearer_token_bedrock" {
  type        = string
  description = "Your AWS Bedrock bearer token. This provides access to Bedrock without needing separate access key and secret key."
  sensitive   = true
  value       = "xxxx-xxx-xxxx"
}

resource "coder_env" "bedrock_api_key" {
  agent_id  = coder_agent.example.id
  name      = "AWS_BEARER_TOKEN_BEDROCK"
  value     = var.aws_bearer_token_bedrock
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "3.1.1"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
  model    = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
```

> [!NOTE]
> For additional Bedrock configuration options (model selection, token limits, region overrides, etc.), see the [Claude Code Bedrock documentation](https://docs.claude.com/en/docs/claude-code/amazon-bedrock).

### Usage with Google Vertex AI

#### Prerequisites

GCP project with Vertex AI API enabled, Claude models enabled through Model Garden, Google Cloud authentication configured, appropriate IAM permissions.

Configure Claude Code to use Google Vertex AI for accessing Claude models through Google Cloud Platform.

```tf
resource "coder_env" "vertex_use" {
  agent_id = coder_agent.example.id
  name     = "CLAUDE_CODE_USE_VERTEX"
  value    = "1"
}

resource "coder_env" "vertex_project_id" {
  agent_id = coder_agent.example.id
  name     = "ANTHROPIC_VERTEX_PROJECT_ID"
  value    = "your-gcp-project-id"
}

resource "coder_env" "cloud_ml_region" {
  agent_id = coder_agent.example.id
  name     = "CLOUD_ML_REGION"
  value    = "global"
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "3.1.1"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
  model    = "claude-sonnet-4@20250514"
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
