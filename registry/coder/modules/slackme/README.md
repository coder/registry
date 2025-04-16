---
display_name: Slack Me
description: Send a Slack message when a command finishes inside a workspace!
icon: ../../../../.icons/slack.svg
maintainer_github: coder
verified: true
tags: [helper]
---

# Slack Me

Add the `slackme` command to your workspace that DMs you on Slack when your command finishes running.

```bash
slackme npm run long-build
```

## Setup

1. Navigate to [Create a Slack App](https://api.slack.com/apps?new_app=1) and select "From an app manifest". Select a workspace and paste in the following manifest, adjusting the redirect URL to your Coder deployment:

   ```json
   {
     "display_information": {
       "name": "Command Notify",
       "description": "Notify developers when commands finish running inside Coder!",
       "background_color": "#1b1b1c"
     },
     "features": {
       "bot_user": {
         "display_name": "Command Notify"
       }
     },
     "oauth_config": {
       "redirect_urls": [
         "https://<your coder deployment>/external-auth/slack/callback"
       ],
       "scopes": {
         "bot": ["chat:write"]
       }
     }
   }
   ```

2. In the "Basic Information" tab on the left after creating your app, scroll down to the "App Credentials" section. Set the following environment variables in your Coder deployment:

   ```env
   CODER_EXTERNAL_AUTH_1_TYPE=slack
   CODER_EXTERNAL_AUTH_1_SCOPES="chat:write"
   CODER_EXTERNAL_AUTH_1_DISPLAY_NAME="Slack Me"
   CODER_EXTERNAL_AUTH_1_CLIENT_ID="<your client id>
   CODER_EXTERNAL_AUTH_1_CLIENT_SECRET="<your client secret>"
   ```

3. Restart your Coder deployment. Any Template can now import the Slack Me module, and `slackme` will be available on the `$PATH`:

   ```tf
   module "slackme" {
     count            = data.coder_workspace.me.start_count
     source           = "registry.coder.com/modules/slackme/coder"
     version          = "1.0.2"
     agent_id         = coder_agent.example.id
     auth_provider_id = "slack"
   }
   ```

## Examples

### Custom Slack Message

- `$COMMAND` is replaced with the command the user executed.
- `$DURATION` is replaced with a human-readable duration the command took to execute.

```tf
module "slackme" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/modules/slackme/coder"
  version          = "1.0.2"
  agent_id         = coder_agent.example.id
  auth_provider_id = "slack"
  slack_message    = <<EOF
👋 Hey there from Coder! $COMMAND took $DURATION to execute!
EOF
}
```
