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
  version        = "4.9.3"
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

## State Persistence

AgentAPI can save and restore its conversation state to disk across workspace restarts. This complements `continue` (which resumes the Claude CLI session) by also preserving the AgentAPI-level context. Enabled by default, requires agentapi >= v0.12.0 (older versions skip it with a warning).

To disable:

```tf
module "claude-code" {
  # ... other config
  enable_state_persistence = false
}
```

## Examples

### Usage with Agent Boundaries

This example shows how to configure the Claude Code module to run the agent behind a process-level boundary that restricts its network access.

By default, when `enable_boundary = true`, the module uses `coder boundary` subcommand (provided by Coder) without requiring any installation.

```tf
module "claude-code" {
  source          = "registry.coder.com/coder/claude-code/coder"
  version         = "4.9.3"
  agent_id        = coder_agent.main.id
  workdir         = "/home/coder/project"
  enable_boundary = true
}
```

> [!NOTE]
> For developers: The module also supports installing boundary from a release version (`use_boundary_directly = true`) or compiling from source (`compile_boundary_from_source = true`). These are escape hatches for development and testing purposes.

### Usage with AI Bridge

[AI Bridge](https://coder.com/docs/ai-coder/ai-bridge) is a Premium Coder feature that provides centralized LLM proxy management. To use AI Bridge, set `enable_aibridge = true`. Requires Coder version >= 2.29.0.

For tasks integration with AI Bridge, add `enable_aibridge = true` to the [Usage with Tasks](#usage-with-tasks) example below.

#### Standalone usage with AI Bridge

```tf
module "claude-code" {
  source          = "registry.coder.com/coder/claude-code/coder"
  version         = "4.9.3"
  agent_id        = coder_agent.main.id
  workdir         = "/home/coder/project"
  enable_aibridge = true
}
```

When `enable_aibridge = true`, the module automatically sets:

- `ANTHROPIC_BASE_URL` to `${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic`
- `CLAUDE_API_KEY` to the workspace owner's session token

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
  source    = "registry.coder.com/coder/claude-code/coder"
  version   = "4.9.3"
  agent_id  = coder_agent.main.id
  workdir   = "/home/coder/project"
  ai_prompt = data.coder_task.me.prompt

  # Optional: route through AI Bridge (Premium feature)
  # enable_aibridge = true
}
```

### Advanced Configuration

This example shows additional configuration options for version pinning, custom models, and MCP servers.

> [!NOTE]
> The `claude_binary_path` variable can be used to specify where a pre-installed Claude binary is located.

> [!WARNING]
> **Deprecation Notice**: The npm installation method (`install_via_npm = true`) will be deprecated and removed in the next major release. Please use the default binary installation method instead.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "4.9.3"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"

  claude_api_key = "xxxx-xxxxx-xxxx"
  # OR
  claude_code_oauth_token = "xxxxx-xxxx-xxxx"

  claude_code_version = "2.0.62"          # Pin to a specific version
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

  mcp_config_remote_path = [
    "https://gist.githubusercontent.com/35C4n0r/cd8dce70360e5d22a070ae21893caed4/raw/",
    "https://raw.githubusercontent.com/coder/coder/main/.mcp.json"
  ]
}
```

> [!NOTE]
> Remote URLs should return a JSON body in the following format:
>
> ```json
> {
>   "mcpServers": {
>     "server-name": {
>       "command": "some-command",
>       "args": ["arg1", "arg2"]
>     }
>   }
> }
> ```
>
> The `Content-Type` header doesn't matter—both `text/plain` and `application/json` work fine.

### Standalone Mode

Run and configure Claude Code as a standalone CLI in your workspace.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "4.9.3"
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
  version                 = "4.9.3"
  agent_id                = coder_agent.main.id
  workdir                 = "/home/coder/project"
  claude_code_oauth_token = var.claude_code_oauth_token
}
```

### Usage with AWS Bedrock

Set `use_bedrock = true` to route Claude Code through Amazon Bedrock. The module sets `CLAUDE_CODE_USE_BEDROCK=1` and skips Anthropic API key setup; authentication is handled by the AWS SDK credential chain inside the workspace.

#### Prerequisites

AWS account with Bedrock access, Claude models enabled in the Bedrock console, and IAM permissions for `bedrock:InvokeModel*` on the workspace's identity.

```tf
module "claude-code" {
  source      = "registry.coder.com/coder/claude-code/coder"
  version     = "4.9.3"
  agent_id    = coder_agent.main.id
  workdir     = "/home/coder/project"
  use_bedrock = true
  model       = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

resource "coder_env" "aws_region" {
  agent_id = coder_agent.main.id
  name     = "AWS_REGION"
  value    = "us-east-1"
}
```

> [!TIP]
> Prefer attaching an IAM role to the workspace (EKS IRSA, EC2 instance profile, or ECS task role) over passing static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` through Terraform variables. Claude Code picks up the role via the standard AWS credential chain with no additional configuration.

If your workspaces cannot use an attached IAM role, you can still pass static credentials or a Bedrock bearer token via `coder_env` resources alongside the module:

```tf
resource "coder_env" "aws_bearer_token_bedrock" {
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}
```

See the [Claude Code Bedrock documentation](https://docs.claude.com/en/docs/claude-code/amazon-bedrock) for region overrides, model selection, and token limit tuning.

### Usage with Google Vertex AI

Set `use_vertex = true` to route Claude Code through Google Vertex AI. The module sets `CLAUDE_CODE_USE_VERTEX=1` and skips Anthropic API key setup; authentication uses Google Application Default Credentials inside the workspace.

#### Prerequisites

A GCP project with the Vertex AI API enabled, Claude models enabled in Model Garden, and the workspace identity granted the `Vertex AI User` role.

```tf
module "claude-code" {
  source     = "registry.coder.com/coder/claude-code/coder"
  version    = "4.9.3"
  agent_id   = coder_agent.main.id
  workdir    = "/home/coder/project"
  use_vertex = true
  model      = "claude-sonnet-4@20250514"
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
```

> [!TIP]
> Prefer GKE Workload Identity or an attached service account over shipping a service-account JSON key through Terraform. Claude Code picks up Application Default Credentials automatically. If you must use a key file, mount it and set `GOOGLE_APPLICATION_CREDENTIALS` via a `coder_env` resource.

See the [Claude Code Vertex AI documentation](https://docs.claude.com/en/docs/claude-code/google-vertex-ai) for additional configuration options.

### Usage with a custom API gateway

Set `anthropic_base_url` to point Claude Code at a self-hosted gateway or proxy that speaks the Anthropic Messages API. The module sets `ANTHROPIC_BASE_URL` and skips its built-in Anthropic authentication setup; provide whatever credentials your gateway requires via `coder_env`.

```tf
module "claude-code" {
  source             = "registry.coder.com/coder/claude-code/coder"
  version            = "4.9.3"
  agent_id           = coder_agent.main.id
  workdir            = "/home/coder/project"
  anthropic_base_url = "https://llm-gateway.example.com/anthropic"
}
```

`anthropic_base_url` is mutually exclusive with `enable_aibridge` (which sets `ANTHROPIC_BASE_URL` to the Coder AI Bridge endpoint automatically).

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
> To use tasks with Claude Code, the workspace must be authenticated to a model provider: set `claude_api_key` or `claude_code_oauth_token` for Anthropic's API, `enable_aibridge = true` for Coder AI Bridge, `use_bedrock = true` / `use_vertex = true` for cloud providers, or `anthropic_base_url` for a custom gateway.
> The `workdir` variable is required and specifies the directory where Claude Code will run.

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
