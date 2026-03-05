---
display_name: "Docker Container"
description: "Develop in a container on a Docker host"
icon: "../../../../.icons/docker.svg"
verified: true
tags: ["docker", "container"]
supported_os: ["linux", "macos"]
---

# Docker Container

Develop in a Docker container on a remote Docker host.

```tf
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 1.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

provider "coder" {}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
}

resource "docker_container" "workspace" {
  image = "codercom/enterprise-base:ubuntu"
  name  = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"

  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
}
```

## Getting Started

This template creates a Docker container on your Docker host. You'll need:

- A Docker host accessible from your Coder deployment
- The Docker provider configured with appropriate credentials

## Customization

You can customize the container image, resources, and configuration to match your needs.
