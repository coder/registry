---
display_name: JFrog (Token)
description: Install the JF CLI and authenticate with Artifactory using Artifactory terraform provider.
icon: ../../../../.icons/jfrog.svg
verified: true
tags: [integration, jfrog]
---

# JFrog

Install the JF CLI and authenticate package managers with Artifactory using Artifactory terraform provider.

```tf
module "jfrog" {
  source                   = "registry.coder.com/coder/jfrog-token/coder"
  version                  = "1.0.31"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  package_managers = {
    npm    = ["npm", "@scoped:npm-scoped"]
    go     = ["go", "another-go-repo"]
    pypi   = ["pypi", "extra-index-pypi"]
    docker = ["example-docker-staging.jfrog.io", "example-docker-production.jfrog.io"]
    conda  = ["conda", "conda-local"]
  }
}
```

For detailed instructions, please see this [guide](https://coder.com/docs/v2/latest/guides/artifactory-integration#jfrog-token) on the Coder documentation.

> Note
> This module does not install `npm`, `go`, `pip`, etc but only configure them. You need to handle the installation of these tools yourself.

![JFrog](../../.images/jfrog.png)

## Examples

### Configure npm, go, and pypi to use Artifactory local repositories

```tf
module "jfrog" {
  source                   = "registry.coder.com/coder/jfrog-token/coder"
  version                  = "1.0.31"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://YYYY.jfrog.io"
  artifactory_access_token = var.artifactory_access_token # An admin access token
  package_managers = {
    npm   = ["npm-local"]
    go    = ["go-local"]
    pypi  = ["pypi-local"]
    conda = ["conda-local"]
  }
}
```

You should now be able to install packages from Artifactory using both the `jf npm`, `jf go`, `jf pip` and `npm`, `go`, `pip`, `conda` commands.

```shell
jf npm install prettier
jf go get github.com/golang/example/hello
jf pip install requests
conda install numpy
```

```shell
npm install prettier
go get github.com/golang/example/hello
pip install requests
conda install numpy
```

### Configure code-server with JFrog extension

The [JFrog extension](https://open-vsx.org/extension/JFrog/jfrog-vscode-extension) for VS Code allows you to interact with Artifactory from within the IDE.

```tf
module "jfrog" {
  source                   = "registry.coder.com/coder/jfrog-token/coder"
  version                  = "1.0.31"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  configure_code_server    = true # Add JFrog extension configuration for code-server
  package_managers = {
    npm  = ["npm"]
    go   = ["go"]
    pypi = ["pypi"]
  }
}
```

### Add a custom token description

```tf
data "coder_workspace" "me" {}

module "jfrog" {
  source                   = "registry.coder.com/coder/jfrog-token/coder"
  version                  = "1.0.31"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  token_description        = "Token for Coder workspace: ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"
  package_managers = {
    npm = ["npm"]
  }
}
```

### Using the access token in other terraform resources

JFrog Access token is also available as a terraform output. You can use it in other terraform resources. For example, you can use it to configure an [Artifactory docker registry](https://jfrog.com/help/r/jfrog-artifactory-documentation/docker-registry) with the [docker terraform provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs).

```tf

provider "docker" {
  # ...
  registry_auth {
    address  = "https://YYYY.jfrog.io/artifactory/api/docker/REPO-KEY"
    username = module.jfrog.username
    password = module.jfrog.access_token
  }
}
```

> Here `REPO_KEY` is the name of docker repository in Artifactory.
