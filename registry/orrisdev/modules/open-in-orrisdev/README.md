---
display_name: Open in OrrisDev
description: Add an OrrisDev launcher and private helper route to an existing Dev Container
icon: ../../../../.icons/terminal.svg
verified: false
tags: [ide, editor, devcontainers, ipad]
---

# Open in OrrisDev

Add **Open in OrrisDev** to an existing Terraform-managed Dev Container. The module registers an external launcher and an owner-private subdomain app for an already installed OrrisDev helper. Both attach to the selected container's sub-agent.

The module installs no software and creates no workspace or Dev Container. Prepare the container, signed trusted helper, persistent storage and private wildcard HTTPS ingress first. Credentials are entered separately in OrrisDev; none belong in Terraform or launch URLs.

```tf
module "open_in_orrisdev" {
  source  = "registry.coder.com/orrisdev/open-in-orrisdev/coder"
  version = "0.1.0"

  subagent_id       = coder_devcontainer.repo[0].subagent_id
  start_count       = data.coder_workspace.me.start_count
  deployment_origin = data.coder_workspace.me.access_url
  workspace_id      = data.coder_workspace.me.id
  config_path       = "/home/coder/repo/.devcontainer/devcontainer.json"
  workspace_folder  = "/home/coder/repo"
}
```

Use the public deployment origin and the exact configuration/folder reported by Coder. The default helper URL is `https://localhost:8443`; set it to the helper's actual configured loopback HTTPS port. Use unique app slugs for multiple containers. Keep both resources on `subagent_id`, rather than the parent agent.

The launcher carries only deployment, workspace UUID, configuration, folder and helper slug. It authorizes nothing. OrrisDev authenticates the account and revalidates the exact container/private helper before attaching. Coder supplies its normal TLS proxy and application authorization behavior.

The two-app configuration is qualified with Coder2.38.7/provider2.20.0 on an iPad simulator. The module has local formatting, provider validation and15 mocked plan-only checks with Terraform1.14.3/provider2.20.0; no apply or broader deployment qualification is claimed. Tests require Terraform1.7 or later.

Start/stop, rebuild, helper installation/enrollment and account administration stay with the environment owner. This module supports explicit Terraform-managed Dev Containers; automatically discovered container customizations and path apps are outside its scope.
