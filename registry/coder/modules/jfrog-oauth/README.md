---
display_name: JFrog (OAuth)
description: Install the JF CLI and authenticate with Artifactory using OAuth.
icon: ../../../../.icons/jfrog.svg
verified: true
tags: [integration, jfrog, helper]
---

# JFrog

Install the JF CLI and authenticate package managers with Artifactory using OAuth configured via the Coder [`external-auth`](https://coder.com/docs/admin/external-auth) feature.

![JFrog OAuth](../../.images/jfrog-oauth.png)

```tf
module "jfrog" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jfrog-oauth/coder"
  version        = "1.2.5"
  agent_id       = coder_agent.main.id
  jfrog_url      = "https://example.jfrog.io"
  username_field = "username" # If you are using GitHub to login to both Coder and Artifactory, use username_field = "username"

  package_managers = {
    npm    = ["npm", "@scoped:npm-scoped"]
    go     = ["go", "another-go-repo"]
    pypi   = ["pypi", "extra-index-pypi"]
    docker = ["example-docker-staging.jfrog.io", "example-docker-production.jfrog.io"]
    conda  = ["conda", "conda-local"]
    maven  = ["maven", "maven-local"]
  }

}
```

> Note
> This module does not install `npm`, `go`, `pip`, etc but only configure them. You need to handle the installation of these tools yourself.

## Prerequisites

This module works with both JFrog SaaS (for example, `example.jfrog.io`) and self-hosted (on-premises) Artifactory. It uses Coder's [external-auth](https://coder.com/docs/admin/external-auth) feature so each user authenticates with Artifactory through an OAuth flow, and Coder issues a user-scoped access token to each workspace.

Using the module requires two things: an application integration in Artifactory and a matching external authentication provider in Coder. The full walkthrough, including the Helm values for self-hosted instances, lives in the [JFrog Artifactory integration guide](https://coder.com/docs/admin/integrations/jfrog-artifactory#jfrog-oauth). The steps below summarize the setup.

## Setup

1. Create an application integration in Artifactory. Use `https://CODER_URL/external-auth/jfrog/callback` (your Coder deployment URL) as the callback/redirect URI and `applied-permissions/user` as the scope.
   - **JFrog SaaS** (`example.jfrog.io`): In the JFrog Platform UI, go to **Administration > General Management > Manage Integrations**, click **New Integration**, and select **External Applications** (or open `https://JFROG_URL/ui/admin/configuration/integrations/application` directly). On the **Create New Application Integration** form, set **Application Name** to `Coder`, set **Application Type** to **Custom Integration**, enter the callback URL above, then click **Generate Client ID & Secret**.
   - **Self-hosted (on-premises)**: First register an integration template in your Helm `values.yaml` (see the [integration guide](https://coder.com/docs/admin/integrations/jfrog-artifactory#jfrog-oauth)), then create the application integration in the UI and select that template as the application type.

   Save the generated **Client ID** and **Client Secret** for the next step.

2. Add a JFrog [external authentication](https://coder.com/docs/admin/external-auth) provider to your Coder deployment. Replace `JFROG_URL` and the client ID and secret with the values from step 1:

   ```dotenv
   # JFrog Artifactory External Auth
   CODER_EXTERNAL_AUTH_1_ID="jfrog"
   CODER_EXTERNAL_AUTH_1_TYPE="jfrog"
   CODER_EXTERNAL_AUTH_1_CLIENT_ID="YYYYYYYYYYYYYYY"
   CODER_EXTERNAL_AUTH_1_CLIENT_SECRET="XXXXXXXXXXXXXXXXXXX"
   CODER_EXTERNAL_AUTH_1_DISPLAY_NAME="JFrog Artifactory"
   CODER_EXTERNAL_AUTH_1_DISPLAY_ICON="/icon/jfrog.svg"
   CODER_EXTERNAL_AUTH_1_AUTH_URL="https://JFROG_URL/ui/authorization"
   CODER_EXTERNAL_AUTH_1_SCOPES="applied-permissions/user"
   ```

   The `external_auth_id` module input defaults to `jfrog` and must match `CODER_EXTERNAL_AUTH_1_ID`.

3. Add this module to your template (see the example above). When a user creates a workspace, Coder prompts them to authenticate with Artifactory and injects a user-scoped token.

## Username Handling

The module automatically extracts your JFrog username directly from the OAuth token's JWT payload. This preserves special characters like dots (`.`), hyphens (`-`), and accented characters that Coder normalizes in usernames.

**Priority order:**

1. **JWT extraction** (default) - Extracts username from OAuth token, preserving special characters
2. **Fallback to `username_field`** - If JWT extraction fails, uses Coder username or email

## Examples

Configure the Python pip package manager to fetch packages from Artifactory while mapping the Coder email to the Artifactory username.

```tf
module "jfrog" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jfrog-oauth/coder"
  version        = "1.2.5"
  agent_id       = coder_agent.main.id
  jfrog_url      = "https://example.jfrog.io"
  username_field = "email"

  package_managers = {
    pypi = ["pypi"]
  }

}
```

You should now be able to install packages from Artifactory using both the `jf pip` and `pip` command.

```shell
jf pip install requests
```

```shell
pip install requests
```

### Configure code-server with JFrog extension

The [JFrog extension](https://open-vsx.org/extension/JFrog/jfrog-vscode-extension) for VS Code allows you to interact with Artifactory from within the IDE.

```tf
module "jfrog" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/coder/jfrog-oauth/coder"
  version               = "1.2.5"
  agent_id              = coder_agent.main.id
  jfrog_url             = "https://example.jfrog.io"
  username_field        = "username" # If you are using GitHub to login to both Coder and Artifactory, use username_field = "username"
  configure_code_server = true       # Add JFrog extension configuration for code-server
  package_managers = {
    npm  = ["npm"]
    go   = ["go"]
    pypi = ["pypi"]
  }

}
```

### Using the access token in other terraform resources

JFrog Access token is also available as a terraform output. You can use it in other terraform resources. For example, you can use it to configure an [Artifactory docker registry](https://jfrog.com/help/r/jfrog-artifactory-documentation/docker-registry) with the [docker terraform provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs).

```tf
provider "docker" {
  # ...
  registry_auth {
    address  = "https://example.jfrog.io/artifactory/api/docker/REPO-KEY"
    username = try(module.jfrog[0].username, "")
    password = try(module.jfrog[0].access_token, "")
  }
}
```

> Here `REPO_KEY` is the name of docker repository in Artifactory.
