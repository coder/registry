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
  version           = "5.3.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}
```

> [!WARNING]
> If upgrading from v4.x.x of this module: v5 is a major refactor that drops support for [Coder Tasks](https://coder.com/docs/ai-coder/tasks) and [Boundary](https://coder.com/docs/ai-coder/agent-firewall). We plan to add those back in a follow-up. Keep using v4.x.x if you depend on them. See [#861](https://github.com/coder/registry/pull/861) for the full migration guide.

## Prerequisites

Provide exactly one authentication method:

- **Anthropic API key**: get one from the [Anthropic Console](https://console.anthropic.com/dashboard) and pass it as `anthropic_api_key`.
- **Claude.ai OAuth token** (Pro, Max, or Enterprise accounts): generate one by running `claude setup-token` locally and pass it as `claude_code_oauth_token`.
- **Coder AI Gateway** (Coder Premium, Coder >= 2.30.0): set `enable_ai_gateway = true`. The module authenticates against the gateway using the workspace owner's session token. Do not combine with `anthropic_api_key` or `claude_code_oauth_token`.
- **Amazon Bedrock**: set `use_bedrock = true`. Authentication uses the workspace's AWS credential chain. See [Usage with AWS Bedrock](#usage-with-aws-bedrock).
- **Google Vertex AI**: set `use_vertex = true`. Authentication uses Google Application Default Credentials inside the workspace. See [Usage with Google Vertex AI](#usage-with-google-vertex-ai).
- **Custom API gateway**: set `anthropic_base_url` to a self-hosted gateway that speaks the Anthropic Messages API. See [Usage with a custom API gateway](#usage-with-a-custom-api-gateway).

## workdir

`workdir` is optional. When set, the module pre-creates the directory if it is missing and pre-accepts the Claude Code trust/onboarding prompt for it in `~/.claude.json`. Leave `workdir` unset if you only want the module to install the CLI and configure authentication; users can still open any project interactively and accept the trust dialog per project.

## Examples

### Standalone mode with a launcher app

Authenticate Claude directly against Anthropic's API and add a `coder_app` that users can click from the workspace dashboard to open an interactive Claude session.

```tf
locals {
  claude_workdir = "/home/coder/project"
}

module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.3.0"
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
  version           = "5.3.0"
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

### Enterprise policy via managed settings

The `managed_settings` input writes a policy file to `/etc/claude-code/managed-settings.d/10-coder.json` inside the workspace. Claude Code reads this directory at startup with the highest configuration precedence, so users cannot override these values in their own `~/.claude/settings.json`. This is a local file mechanism and works with any inference backend (Anthropic API, AWS Bedrock, Google Vertex AI, or AI Gateway).

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.3.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  anthropic_api_key = "xxxx-xxxxx-xxxx"

  managed_settings = {
    permissions = {
      defaultMode                  = "acceptEdits"
      disableBypassPermissionsMode = "disable"
      deny                         = ["Bash(curl:*)", "Bash(wget:*)", "WebFetch"]
    }
    env = {
      DISABLE_TELEMETRY = "0"
    }
  }
}
```

See the [Claude Code settings reference](https://docs.anthropic.com/en/docs/claude-code/settings) for the full schema. Common keys: `permissions` (`defaultMode`, `allow`, `deny`, `disableBypassPermissionsMode`, `additionalDirectories`), `env`, `model`, `apiKeyHelper`, `hooks`, `cleanupPeriodDays`.

### Advanced Configuration

This example shows version pinning, a pre-installed binary path, a custom model, and MCP servers.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.3.0"
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
> Servers configured through `mcp` or `mcp_config_remote_path` are added at Claude Code's [user scope](https://docs.claude.com/en/docs/claude-code/mcp#scope), making them available across every project the workspace owner opens. For project-local MCP servers, commit a `.mcp.json` to the project repository instead.

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
  version           = "5.3.0"
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

Set `use_bedrock = true` to route Claude Code through Amazon Bedrock. The module sets `CLAUDE_CODE_USE_BEDROCK=1` and skips Anthropic API key setup; authentication is handled by the AWS SDK [credential chain](https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html) inside the workspace.

```tf
module "claude-code" {
  source      = "registry.coder.com/coder/claude-code/coder"
  version     = "5.3.0"
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
> Prefer attaching an IAM role to the workspace (EKS [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html), EC2 instance profile, or ECS task role) over passing static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` through Terraform variables. Claude Code picks up the role via the standard AWS credential chain with no additional configuration.

If you cannot use an attached role, set static credentials via `coder_env` resources:

```tf
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
```

Or use a [Bedrock API key](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html) instead of access-key/secret-key:

```tf
resource "coder_env" "bedrock_api_key" {
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}
```

> [!NOTE]
> Prerequisites: AWS account with Bedrock access, Claude models enabled in the Bedrock console, and IAM permission `bedrock:InvokeModelWithResponseStream`. For additional configuration (token limits, region overrides), see the [Claude Code Bedrock documentation](https://docs.claude.com/en/docs/claude-code/amazon-bedrock).

### Usage with Google Vertex AI

Set `use_vertex = true` to route Claude Code through Google Vertex AI. The module sets `CLAUDE_CODE_USE_VERTEX=1` and skips Anthropic API key setup; authentication uses [Google Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) inside the workspace.

```tf
module "claude-code" {
  source     = "registry.coder.com/coder/claude-code/coder"
  version    = "5.3.0"
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
> Prefer GKE [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) or an attached service account over shipping a service-account JSON key through Terraform. Claude Code picks up Application Default Credentials automatically. If you must use a key file, mount it and set `GOOGLE_APPLICATION_CREDENTIALS` via a `coder_env` resource.

> [!NOTE]
> Prerequisites: GCP project with Vertex AI API enabled, Claude models enabled through Model Garden, and the `Vertex AI User` role on the workspace identity. For additional configuration, see the [Claude Code Vertex AI documentation](https://docs.claude.com/en/docs/claude-code/google-vertex-ai).

### Usage with a custom API gateway

Set `anthropic_base_url` to point Claude Code at a self-hosted gateway or proxy that speaks the Anthropic Messages API. The module sets `ANTHROPIC_BASE_URL` and skips its built-in Anthropic authentication setup; provide whatever credentials your gateway requires via separate `coder_env` resources.

```tf
module "claude-code" {
  source             = "registry.coder.com/coder/claude-code/coder"
  version            = "5.3.0"
  agent_id           = coder_agent.main.id
  workdir            = "/home/coder/project"
  anthropic_base_url = "https://llm-gateway.example.com/anthropic"
}
```

> [!CAUTION]
> `anthropic_base_url` is mutually exclusive with `enable_ai_gateway`, which sets `ANTHROPIC_BASE_URL` to the Coder AI Gateway endpoint. `use_bedrock` and `use_vertex` are likewise mutually exclusive with `enable_ai_gateway` and with each other.

### Telemetry export (OpenTelemetry)

Claude Code can emit OpenTelemetry metrics and events covering token usage, tool calls, session lifecycle, and errors (see the [monitoring docs](https://docs.anthropic.com/en/docs/claude-code/monitoring-usage)). Set `telemetry.enabled = true` and point `otlp_endpoint` at your OTLP collector.

The module automatically tags every span and metric with `coder.workspace_id`, `coder.workspace_name`, `coder.workspace_owner`, and `coder.template_name` via `OTEL_RESOURCE_ATTRIBUTES`, so Claude Code telemetry can be joined directly against Coder's [audit logs](https://coder.com/docs/admin/security/audit-logs) and `exectrace` records on `workspace_id`.

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.3.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  anthropic_api_key = "xxxx-xxxxx-xxxx"

  telemetry = {
    enabled       = true
    otlp_endpoint = "http://otel-collector.observability:4317"
    otlp_protocol = "grpc"
    otlp_headers = {
      authorization = "Bearer ${var.otel_token}"
    }
    resource_attributes = {
      "service.name" = "claude-code"
    }
  }
}
```

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
