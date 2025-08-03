---
display_name: JFrog Maven (Token)
description: Install the JF CLI and configure Maven with Artifactory using Artifactory terraform provider.
icon: ../../../../.icons/jfrog.svg
verified: true
tags: [integration, jfrog, maven]
---

# JFrog Maven

Install the JF CLI and configure Maven with Artifactory using Artifactory terraform provider.

```tf
module "jfrog_maven" {
  source                   = "registry.coder.com/coder/jfrog-maven-token/coder"
  version                  = "1.0.0"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  maven_repositories       = ["maven-local", "maven-remote", "maven-virtual"]
}
```

For detailed instructions, please see this [guide](https://coder.com/docs/v2/latest/guides/artifactory-integration#jfrog-token) on the Coder documentation.

> Note
> This module does not install Maven but only configures it. You need to handle the installation of Maven yourself.

![JFrog Maven](../../.images/jfrog-maven.png)

## Examples

### Configure Maven with Artifactory local repositories

```tf
module "jfrog_maven" {
  source                   = "registry.coder.com/coder/jfrog-maven-token/coder"
  version                  = "1.0.0"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://YYYY.jfrog.io"
  artifactory_access_token = var.artifactory_access_token # An admin access token
  maven_repositories       = ["maven-local", "maven-remote"]
}
```

You should now be able to use Maven with Artifactory repositories:

```shell
jf mvn clean install
```

```shell
mvn clean install
```

### Configure code-server with JFrog extension

The [JFrog extension](https://open-vsx.org/extension/JFrog/jfrog-vscode-extension) for VS Code allows you to interact with Artifactory from within the IDE.

```tf
module "jfrog_maven" {
  source                   = "registry.coder.com/coder/jfrog-maven-token/coder"
  version                  = "1.0.0"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  configure_code_server    = true # Add JFrog extension configuration for code-server
  maven_repositories       = ["maven-local"]
}
```

### Add a custom token description

```tf
data "coder_workspace" "me" {}

module "jfrog_maven" {
  source                   = "registry.coder.com/coder/jfrog-maven-token/coder"
  version                  = "1.0.0"
  agent_id                 = coder_agent.example.id
  jfrog_url                = "https://XXXX.jfrog.io"
  artifactory_access_token = var.artifactory_access_token
  token_description        = "Token for Coder workspace: ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"
  maven_repositories       = ["maven-local"]
}
```

### Using the access token in other terraform resources

JFrog Access token is also available as a terraform output. You can use it in other terraform resources.

```tf
output "jfrog_access_token" {
  value = module.jfrog_maven.access_token
  sensitive = true
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `agent_id` | The ID of a Coder agent. | `string` | n/a | yes |
| `jfrog_url` | JFrog instance URL. e.g. https://myartifactory.jfrog.io | `string` | n/a | yes |
| `artifactory_access_token` | The admin-level access token to use for JFrog. | `string` | n/a | yes |
| `maven_repositories` | List of Maven repository keys to configure. | `list(string)` | `[]` | no |
| `username_field` | The field to use for the artifactory username. | `string` | `"username"` | no |
| `username` | Username to use for Artifactory. | `string` | `null` | no |
| `jfrog_server_id` | The server ID of the JFrog instance for JFrog CLI configuration. | `string` | `"0"` | no |
| `token_description` | Free text token description. | `string` | `"Token for Coder workspace"` | no |
| `check_license` | Toggle for pre-flight checking of Artifactory license. | `bool` | `true` | no |
| `refreshable` | Is this token refreshable? | `bool` | `false` | no |
| `expires_in` | The amount of time, in seconds, it would take for the token to expire. | `number` | `null` | no |
| `configure_code_server` | Set to true to configure code-server to use JFrog. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `access_token` | The JFrog access token |
| `username` | The JFrog username | 