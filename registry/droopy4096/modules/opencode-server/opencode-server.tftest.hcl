mock_provider "coder" {}

run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }
}

run "defaults" {
  command = apply

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = output.port == 4096
    error_message = "Expected default port 4096."
  }

  assert {
    condition     = output.server_url == "http://127.0.0.1:4096"
    error_message = "Expected server_url to use loopback and the default port."
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "Expected install + start scripts."
  }

  assert {
    condition     = length(coder_app.attach) == 1
    error_message = "Expected the attach app by default."
  }

  assert {
    condition     = length(coder_env.ai_gateway_token) == 0
    error_message = "AI Gateway env must be off by default."
  }
}

run "ai_gateway_sets_env" {
  command = apply

  variables {
    agent_id          = "example-agent-id"
    enable_ai_gateway = true
  }

  assert {
    condition     = length(coder_env.ai_gateway_url) == 1 && length(coder_env.ai_gateway_token) == 1
    error_message = "Expected AI Gateway URL and token env vars."
  }

  assert {
    condition     = endswith(coder_env.ai_gateway_url[0].value, "/api/v2/ai-gateway")
    error_message = "Expected the AI Gateway base path."
  }
}

run "no_app" {
  command = apply

  variables {
    agent_id = "example-agent-id"
    web_app  = false
  }

  assert {
    condition     = length(coder_app.attach) == 0
    error_message = "Expected no attach app when web_app = false."
  }
}

run "custom_port" {
  command = apply

  variables {
    agent_id = "example-agent-id"
    port     = 8080
  }

  assert {
    condition     = output.server_url == "http://127.0.0.1:8080"
    error_message = "Expected server_url to use the custom port."
  }

  assert {
    condition     = coder_app.attach[0].slug == "opencode-server-8080" && output.scripts[0] == "droopy4096-opencode-server-8080-install_script"
    error_message = "Expected a port-specific app slug and sync names so instances do not collide."
  }
}

run "pinned_1x_version_allowed" {
  command = plan

  variables {
    agent_id         = "example-agent-id"
    opencode_version = "1.19.5"
  }
}

run "v2_version_rejected" {
  command = plan

  variables {
    agent_id         = "example-agent-id"
    opencode_version = "2.0.27"
  }

  expect_failures = [var.opencode_version]
}

run "invalid_port_rejected" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    port     = 70000
  }

  expect_failures = [var.port]
}

run "autoupdate_disabled_by_default" {
  command = apply

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = keys(coder_env.opencode) == ["OPENCODE_DISABLE_AUTOUPDATE"]
    error_message = "Expected only OPENCODE_DISABLE_AUTOUPDATE by default."
  }
}

run "autoupdate_allowed" {
  command = apply

  variables {
    agent_id           = "example-agent-id"
    disable_autoupdate = false
  }

  assert {
    condition     = length(coder_env.opencode) == 0
    error_message = "Expected no OpenCode env vars when autoupdate is allowed."
  }
}

run "offline_disables_outbound_calls" {
  command = apply

  variables {
    agent_id           = "example-agent-id"
    offline            = true
    disable_autoupdate = false
  }

  assert {
    condition = alltrue([
      for name in [
        "OPENCODE_DISABLE_AUTOUPDATE",
        "OPENCODE_DISABLE_MODELS_FETCH",
        "OPENCODE_DISABLE_DEFAULT_PLUGINS",
        "OPENCODE_DISABLE_LSP_DOWNLOAD",
      ] : coder_env.opencode[name].value == "true"
    ])
    error_message = "Expected offline to set every OpenCode network switch, even with disable_autoupdate = false."
  }
}
