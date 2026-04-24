---
display_name: Claude Code
description: Install and configure the Claude Code CLI in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, anthropic, ai-gateway]
---

# Claude Code

Install and configure the [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) CLI in your workspace. Starting Claude is left to the caller (template command, IDE launcher, or a custom `coder_script`).

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}
```

## workdir

`workdir` is optional. When set, the module pre-creates the directory if it is missing and pre-accepts the Claude Code trust/onboarding prompt for it in `~/.claude.json`. Leave `workdir` unset if you only want the module to install the CLI and configure authentication; users can still open any project interactively and accept the trust dialog per project.

## MCP scope

Servers configured through `mcp` or `mcp_config_remote_path` are added at Claude Code's [user scope](https://docs.claude.com/en/docs/claude-code/mcp#scope), which makes them available across every project the workspace owner opens. For project-local MCP servers, commit a `.mcp.json` file to the project repository instead of passing it through this module.

## Prerequisites

Provide exactly one authentication method:

- **Anthropic API key**: get one from the [Anthropic Console](https://console.anthropic.com/dashboard) and pass it as `anthropic_api_key`.
- **Claude.ai OAuth token** (Pro, Max, or Enterprise accounts): generate one by running `claude setup-token` locally and pass it as `claude_code_oauth_token`.
- **Coder AI Gateway** (Coder Premium, Coder >= 2.30.0): set `enable_ai_gateway = true`. The module authenticates against the gateway using the workspace owner's session token. Do not combine with `anthropic_api_key` or `claude_code_oauth_token`.

## Examples

### Standalone mode with a launcher app

Authenticate Claude directly against Anthropic's API and add a `coder_app` that users can click from the workspace dashboard to open an interactive Claude session.

```tf
locals {
  claude_workdir = "/home/coder/project"
}

module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  workdir           = local.claude_workdir
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}

resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    cd ${local.claude_workdir}
    claude
  EOT
}
```

> [!NOTE]
> `coder_app.command` runs when the user clicks the app tile. Combine with `anthropic_api_key`, `claude_code_oauth_token`, or `enable_ai_gateway = true` on the module to pre-authenticate the CLI.

### Usage with AI Gateway

[AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) is a Premium Coder feature that provides centralized LLM proxy management. Requires Coder >= 2.30.0.

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  enable_ai_gateway = true
}
```

When `enable_ai_gateway = true`, the module sets:

- `ANTHROPIC_BASE_URL` to `${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic`
- `ANTHROPIC_AUTH_TOKEN` to the workspace owner's Coder session token

Claude Code then routes API requests through Coder's AI Gateway instead of directly to Anthropic.

> [!CAUTION]
> `enable_ai_gateway = true` is mutually exclusive with `anthropic_api_key` and `claude_code_oauth_token`. Setting any of them together fails at plan time.

### Advanced Configuration

This example shows version pinning, a pre-installed binary path, a custom model, and MCP servers.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"

  anthropic_api_key = "xxxx-xxxxx-xxxx"

  claude_code_version = "2.0.62" # Pin to a specific Claude CLI version.

  # Skip the module's installer and point at a pre-installed Claude binary.
  # claude_binary_path can only be customized when install_claude_code is false.
  install_claude_code = false
  claude_binary_path  = "/opt/claude/bin"

  model = "sonnet"

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
> Swap `anthropic_api_key` for `claude_code_oauth_token = "xxxxx-xxxx-xxxx"` to authenticate via a Claude.ai OAuth token instead. Pass exactly one.

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
> The `Content-Type` header doesn't matter, both `text/plain` and `application/json` work fine.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `coder exp sync` name of each script it creates via the `scripts` output: an ordered list (`pre_install`, `install`, `post_install`) of names for scripts this module actually creates. Scripts that were not configured are absent from the list.

Downstream `coder_script` resources can wait for this module's install pipeline to finish using `coder exp sync want <self> <each name>`:

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}

resource "coder_script" "post_claude" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Claude Code install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    trap 'coder exp sync complete post-claude' EXIT
    coder exp sync want post-claude ${join(" ", module.claude-code.scripts)}
    coder exp sync start post-claude

    # Your work here runs after claude-code finishes installing.
    claude --version
  EOT
}
```

### Usage with AWS Bedrock

#### Prerequisites

AWS account with Bedrock access, Claude models enabled in Bedrock console, and appropriate IAM permissions.

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
}

variable "aws_secret_access_key" {
  type        = string
  description = "Your AWS secret access key. This is shown once when you create an access key in the AWS IAM console."
  sensitive   = true
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
}

resource "coder_env" "bedrock_api_key" {
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
  model    = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
```

> [!NOTE]
> For additional Bedrock configuration options (model selection, token limits, region overrides, etc.), see the [Claude Code Bedrock documentation](https://docs.claude.com/en/docs/claude-code/amazon-bedrock).

### Usage with Google Vertex AI

#### Prerequisites

GCP project with Vertex AI API enabled, Claude models enabled through Model Garden, service account with Vertex AI permissions, and appropriate IAM permissions (Vertex AI User role).

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
  version  = "5.0.0"
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

If you encounter any issues, check the log files in the `~/.coder-modules/coder/claude-code/logs` directory within your workspace for detailed information.

```bash
# Installation logs
cat ~/.coder-modules/coder/claude-code/logs/install.log

# Pre/post install script logs
cat ~/.coder-modules/coder/claude-code/logs/pre_install.log
cat ~/.coder-modules/coder/claude-code/logs/post_install.log
```

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
