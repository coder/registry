terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "auth_provider_id" {
  type        = string
  description = "The ID of an external auth provider."
}

variable "slack_message" {
  type        = string
  description = "The message to send to Slack."
  default     = "👨‍💻 `$COMMAND` completed in $DURATION"
}

resource "coder_script" "install_slackme" {
  agent_id     = var.agent_id
  display_name = "install_slackme"
  run_on_start = true
  script = <<OUTER
    #!/usr/bin/env bash
    set -e

    CODER_DIR=$(dirname $(which coder))
    cat > $CODER_DIR/slackme <<INNER
${replace(templatefile("${path.module}/slackme.sh", {
  PROVIDER_ID : var.auth_provider_id,
  SLACK_MESSAGE : replace(var.slack_message, "`", "\\`"),
}), "$", "\\$")}
INNER

    chmod +x $CODER_DIR/slackme
    OUTER 
}
