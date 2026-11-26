---
display_name: VS Code Live Share
description: Open a workspace in VS Code Desktop and start a Live Share session
icon: ../../../../.icons/code.svg
verified: false
tags: [ide, vscode, collaboration]
---

# VS Code Live Share

Add an **Open Liveshare** button that opens a specific workspace folder in VS Code Desktop. After you confirm sharing in that window, the Coder extension installs Microsoft Live Share if needed, starts a session, and copies its invitation link to your clipboard. Live Share may ask you to sign in first.

> [!IMPORTANT]
> This module requires the companion Live Share launch support in the [Coder VS Code extension](https://github.com/coder/vscode-coder). That support is not available in the published 1.18.3 extension. For local testing, install the companion development build. Older extensions open the folder but do not start sharing.

```tf
module "liveshare" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-liveshare/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

The folder must be an absolute path on the workspace host. For a workspace with multiple agents, set `agent_name` to the name of the agent attached to the button to avoid the agent picker. Use one folder per Live Share window; multi-root workspaces are not shared by this action.

The module can be used alongside [VS Code Desktop](../vscode-desktop). Ordinary VS Code launches do not install Live Share or start sharing. It does not install a server-side script or change workspace extension settings.

## Connection and sharing

VS Code Desktop and the Coder extension must be installed on the user's computer, and the workspace must support the existing Remote SSH connection. The selected folder must be trusted in VS Code. The sharing request expires after five minutes and is consumed once, including when sharing is cancelled. If connection or sign-in fails, click **Open Liveshare** again.

Live Share uses Microsoft's collaboration service and its authentication providers. The client needs access to the Visual Studio Marketplace to install the extension and to the [Live Share connectivity endpoints](https://learn.microsoft.com/en-us/visualstudio/liveshare/reference/connectivity) during sharing. This is not an offline collaboration solution. Share the invitation link only with intended participants and stop the session using Live Share when finished.
