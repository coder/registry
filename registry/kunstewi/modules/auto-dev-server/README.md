---
display_name: Auto npm start
description: Automatically starts a Node.js development server via `npm start`.
icon: ../../../../.icons/node.svg
maintainer_github: kunstewi
verified: false
tags: [helper, nodejs, automation, dev-server]
---

# Auto npm start

This module automatically detects a Node.js project in your workspace and runs `npm start` in the background when the workspace starts.

It looks for a `package.json` file in the specified project directory. If found, it starts the server and logs the output to `auto-npm-start.log` within that directory.

## Basic Usage

Add this to your Coder template. It will check for a project in `/home/coder/project`.

```tf
module "auto_npm_start" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/auto-npm-start/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Custom Project Directory

If your project is in a different location, you can specify the `project_dir` variable.

```tf
module "auto_npm_start" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/thezoker/auto-npm-start/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  project_dir = "/home/coder/my-awesome-app"
}
```