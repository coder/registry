---
display_name: Sonatype Nexus Repository
description: Configure package managers to use Sonatype Nexus Repository for Maven, npm, PyPI, and Docker registries.
icon: /.icons/nexus.svg
verified: false
tags: [integration, nexus, maven, npm, pypi, docker]
---

# Sonatype Nexus Repository

Configure package managers (Maven, npm, PyPI, Docker) to use [Sonatype Nexus Repository](https://help.sonatype.com/en/sonatype-nexus-repository.html) with API token authentication. This module provides secure credential handling, multiple repository support per package manager, and flexible username configuration.

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    maven  = ["maven-public", "maven-releases"]
    npm    = ["npm-public", "@scoped:npm-private"]
    pypi   = ["pypi-public", "pypi-private"]
    docker = ["docker-public", "docker-private"]
  }
}
```

## Requirements

- Nexus Repository Manager 3.x
- Valid API token or user credentials
- Package managers installed on the workspace (Maven, npm, pip, Docker as needed)

> [!NOTE]
> This module configures package managers but does not install them. You need to handle the installation of Maven, npm, Python pip, and Docker yourself.

## Examples

### Configure Maven to use Nexus repositories

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    maven = ["maven-public", "maven-releases", "maven-snapshots"]
  }
}
```

### Configure npm with scoped packages

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    npm = ["npm-public", "@mycompany:npm-private"]
  }
}
```

### Configure Python PyPI repositories

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    pypi = ["pypi-public", "pypi-private"]
  }
}
```

### Configure Docker registries

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    docker = ["docker-public", "docker-private"]
  }
}
```

### Use custom username

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_username = "custom-user"
  nexus_password = var.nexus_api_token
  package_managers = {
    maven = ["maven-public"]
  }
}
```

### Complete configuration for all package managers

```tf
module "nexus" {
  source         = "registry.coder.com/mavrickrishi/nexus/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  nexus_url      = "https://nexus.example.com"
  nexus_password = var.nexus_api_token
  package_managers = {
    maven  = ["maven-public", "maven-releases"]
    npm    = ["npm-public", "@company:npm-private"]
    pypi   = ["pypi-public", "pypi-private"]
    docker = ["docker-public", "docker-private"]
  }
}
```
