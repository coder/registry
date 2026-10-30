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
