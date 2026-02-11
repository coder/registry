---
display_name: AI Bridge Proxy
description: Configure a workspace to route AI tool traffic through AI Bridge via AI Bridge Proxy.
icon: ../../../../.icons/coder.svg
verified: true
tags: [helper, aibridge]
---

# AI Bridge Proxy

This module configures a Coder workspace to use [AI Bridge Proxy](https://coder.com/docs/ai-coder/ai-bridge/ai-bridge-proxy).
It downloads the proxy's CA certificate from the Coder deployment and exposes outputs that tool-specific modules can use to route their traffic through the proxy.

```tf
module "aibridge-proxy" {
  source    = "registry.coder.com/coder/aibridge-proxy/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  proxy_url = "https://aiproxy.example.com"
}
```

> [!NOTE]
> AI Bridge Proxy is a Premium Coder feature that requires [AI Bridge](https://coder.com/docs/ai-coder/ai-bridge) to be enabled.
> See the [AI Bridge Proxy setup guide](https://coder.com/docs/ai-coder/ai-bridge/ai-bridge-proxy/setup) for details on configuring the proxy on your Coder deployment.

## How it works

AI Bridge Proxy is an HTTP proxy that intercepts traffic to AI providers and forwards it through [AI Bridge](https://coder.com/docs/ai-coder/ai-bridge), enabling centralized LLM management, governance, and cost tracking.
Any process with the proxy environment variables set will route **all** its traffic through the proxy.

This module does **not** set proxy environment variables globally on the workspace.
Instead, it provides outputs (`proxy_auth_url` and `cert_path`) for use by tool-specific modules.
It is recommended that tool modules scope the proxy environment variables to their own process rather than setting them globally on the workspace, to avoid routing unnecessary traffic through the proxy.

> [!WARNING]
> If the setup script fails (e.g. the proxy is unreachable), the workspace will still start but the agent will report a startup script error.
> Tools that depend on the proxy will not work until the issue is resolved. Check the workspace build logs for details.

## Examples

### Custom certificate path

```tf
module "aibridge-proxy" {
  source    = "registry.coder.com/coder/aibridge-proxy/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  proxy_url = "https://aiproxy.example.com"
  cert_path = "/home/coder/.certs/aibridge-proxy-ca.pem"
}
```

### Proxy with custom port

For deployments where the proxy is accessed directly on a configured port.
See [security considerations](https://coder.com/docs/ai-coder/ai-bridge/ai-bridge-proxy/setup#security-considerations) for network access guidelines.

```tf
module "aibridge-proxy" {
  source    = "registry.coder.com/coder/aibridge-proxy/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  proxy_url = "http://internal-proxy:8888"
}
```
