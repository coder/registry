---
display_name: JFrog Maven
description: Install the JF CLI and configure Maven with Artifactory using OAuth.
icon: ../../../../.icons/jfrog.svg
verified: true
tags: [integration, jfrog, maven, helper]
---

# JFrog Maven

Install the JF CLI and configure Maven with Artifactory using OAuth configured via the Coder [`external-auth`](https://coder.com/docs/v2/latest/admin/external-auth) feature.

![JFrog Maven](../../.images/jfrog-maven.png)

```tf
module "jfrog_maven" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jfrog-maven/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  jfrog_url      = "https://example.jfrog.io"
  username_field = "username" # If you are using GitHub to login to both Coder and Artifactory, use username_field = "username"

  maven_repositories = ["maven-local", "maven-remote", "maven-virtual"]
}
```

> Note
> This module does not install Maven but only configures it. You need to handle the installation of Maven yourself.

## Prerequisites

This module is usable by JFrog self-hosted (on-premises) Artifactory as it requires configuring a custom integration. This integration benefits from Coder's [external-auth](https://coder.com/docs/v2/latest/admin/external-auth) feature and allows each user to authenticate with Artifactory using an OAuth flow and issues user-scoped tokens to each user. For configuration instructions, see this [guide](https://coder.com/docs/v2/latest/guides/artifactory-integration#jfrog-oauth) on the Coder documentation.

## Examples

### Configure Maven with Artifactory repositories

Configure Maven to fetch dependencies from Artifactory while mapping the Coder username to the Artifactory username.

```tf
module "jfrog_maven" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jfrog-maven/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  jfrog_url      = "https://example.jfrog.io"
  username_field = "username"

  maven_repositories = ["maven-local", "maven-remote"]
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
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/coder/jfrog-maven/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.example.id
  jfrog_url             = "https://example.jfrog.io"
  username_field        = "username"
  configure_code_server = true       # Add JFrog extension configuration for code-server
  maven_repositories    = ["maven-local"]
}
```

### Using the access token in other terraform resources

JFrog Access token is also available as a terraform output. You can use it in other terraform resources.

```tf
output "jfrog_access_token" {
  value = module.jfrog_maven[0].access_token
  sensitive = true
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `agent_id` | The ID of a Coder agent. | `string` | n/a | yes |
| `jfrog_url` | JFrog instance URL. e.g. https://myartifactory.jfrog.io | `string` | n/a | yes |
| `maven_repositories` | List of Maven repository keys to configure. | `list(string)` | `[]` | no |
| `username_field` | The field to use for the artifactory username. | `string` | `"username"` | no |
| `jfrog_server_id` | The server ID of the JFrog instance for JFrog CLI configuration. | `string` | `"0"` | no |
| `external_auth_id` | JFrog external auth ID. | `string` | `"jfrog"` | no |
| `configure_code_server` | Set to true to configure code-server to use JFrog. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `access_token` | The JFrog access token |
| `username` | The JFrog username | 