mock_provider "coder" {}

run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-123"
  }

  assert {
    condition     = var.http_server_port == 7800
    error_message = "Default port should be 7800"
  }

  assert {
    condition     = var.http_server_log_path == "/tmp/open-webui.log"
    error_message = "Default log path should be /tmp/open-webui.log"
  }

  assert {
    condition     = var.share == "owner"
    error_message = "Default share should be 'owner'"
  }

  assert {
    condition     = var.open_webui_version == "latest"
    error_message = "Default version should be 'latest'"
  }

  assert {
    condition     = coder_app.open-webui.subdomain == true
    error_message = "App should use subdomain"
  }

  assert {
    condition     = coder_app.open-webui.display_name == "Open WebUI"
    error_message = "App display name should be 'Open WebUI'"
  }
}

run "test_custom_port" {
  command = plan

  variables {
    agent_id         = "test-agent-456"
    http_server_port = 9000
  }

  assert {
    condition     = var.http_server_port == 9000
    error_message = "Custom port should be 9000"
  }

  assert {
    condition     = coder_app.open-webui.url == "http://localhost:9000"
    error_message = "App URL should use custom port"
  }
}

run "test_custom_log_path" {
  command = plan

  variables {
    agent_id             = "test-agent-789"
    http_server_log_path = "/var/log/open-webui.log"
  }

  assert {
    condition     = var.http_server_log_path == "/var/log/open-webui.log"
    error_message = "Custom log path should be set"
  }
}

run "test_share_authenticated" {
  command = plan

  variables {
    agent_id = "test-agent-auth"
    share    = "authenticated"
  }

  assert {
    condition     = coder_app.open-webui.share == "authenticated"
    error_message = "Share should be 'authenticated'"
  }
}

run "test_share_public" {
  command = plan

  variables {
    agent_id = "test-agent-public"
    share    = "public"
  }

  assert {
    condition     = coder_app.open-webui.share == "public"
    error_message = "Share should be 'public'"
  }
}

run "test_order_and_group" {
  command = plan

  variables {
    agent_id = "test-agent-order"
    order    = 10
    group    = "AI Tools"
  }

  assert {
    condition     = coder_app.open-webui.order == 10
    error_message = "Order should be 10"
  }

  assert {
    condition     = coder_app.open-webui.group == "AI Tools"
    error_message = "Group should be 'AI Tools'"
  }
}

run "test_custom_version" {
  command = plan

  variables {
    agent_id           = "test-agent-version"
    open_webui_version = "0.5.0"
  }

  assert {
    condition     = var.open_webui_version == "0.5.0"
    error_message = "Custom version should be '0.5.0'"
  }
}

run "test_custom_data_dir" {
  command = plan

  variables {
    agent_id = "test-agent-data"
    data_dir = "/home/coder/open-webui-data"
  }

  assert {
    condition     = var.data_dir == "/home/coder/open-webui-data"
    error_message = "Custom data_dir should be set"
  }
}

run "test_default_data_dir" {
  command = plan

  variables {
    agent_id = "test-agent-data-default"
  }

  assert {
    condition     = var.data_dir == ".open-webui"
    error_message = "Default data_dir should be '.open-webui'"
  }
}

run "test_openai_api_key" {
  command = plan

  variables {
    agent_id       = "test-agent-openai"
    openai_api_key = "sk-test-key-123"
  }

  assert {
    condition     = var.openai_api_key == "sk-test-key-123"
    error_message = "OpenAI API key should be set"
  }
}

run "test_default_openai_api_key" {
  command = plan

  variables {
    agent_id = "test-agent-openai-default"
  }

  assert {
    condition     = var.openai_api_key == ""
    error_message = "Default OpenAI API key should be empty"
  }
}
