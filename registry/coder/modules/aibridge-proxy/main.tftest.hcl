run "test_aibridge_proxy_basic" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
  }

  assert {
    condition     = var.agent_id == "test-agent-id"
    error_message = "Agent ID should match the input variable"
  }

  assert {
    condition     = var.proxy_url == "https://aiproxy.example.com"
    error_message = "Proxy URL should match the input variable"
  }

  assert {
    condition     = var.cert_path == "/tmp/aibridge-proxy/ca-cert.pem"
    error_message = "cert_path should default to /tmp/aibridge-proxy/ca-cert.pem"
  }
}

run "test_aibridge_proxy_empty_url_validation" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = ""
  }

  expect_failures = [
    var.proxy_url,
  ]
}

run "test_aibridge_proxy_invalid_url_validation" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "aiproxy.example.com"
  }

  expect_failures = [
    var.proxy_url,
  ]
}

run "test_aibridge_proxy_url_formats" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
  }

  assert {
    condition     = can(regex("^https?://", var.proxy_url))
    error_message = "Proxy URL should be a valid URL with scheme"
  }
}

run "test_aibridge_proxy_https_with_port" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com:8443"
  }

  assert {
    condition     = can(regex("^https?://", var.proxy_url))
    error_message = "Proxy URL should support HTTPS with custom port"
  }
}

run "test_aibridge_proxy_http_with_port" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "http://internal-proxy:8888"
  }

  assert {
    condition     = can(regex("^https?://", var.proxy_url))
    error_message = "Proxy URL should support HTTP with custom port"
  }
}

run "test_aibridge_proxy_empty_cert_path_validation" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
    cert_path = ""
  }

  expect_failures = [
    var.cert_path,
  ]
}

run "test_aibridge_proxy_relative_cert_path_validation" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
    cert_path = "relative/path/ca-cert.pem"
  }

  expect_failures = [
    var.cert_path,
  ]
}

run "test_aibridge_proxy_custom_cert_path" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
    cert_path = "/home/coder/.certs/ca-cert.pem"
  }

  assert {
    condition     = var.cert_path == "/home/coder/.certs/ca-cert.pem"
    error_message = "cert_path should match the input variable"
  }
}

run "test_aibridge_proxy_script" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
  }

  assert {
    condition     = coder_script.aibridge_proxy_setup.run_on_start == true
    error_message = "Script should run on start"
  }

  assert {
    condition     = coder_script.aibridge_proxy_setup.start_blocks_login == false
    error_message = "Script should not block login"
  }

  assert {
    condition     = coder_script.aibridge_proxy_setup.display_name == "AI Bridge Proxy Setup"
    error_message = "Script display name should be 'AI Bridge Proxy Setup'"
  }
}

run "test_aibridge_proxy_auth_url_https" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "https://aiproxy.example.com"
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = output.proxy_auth_url == "https://coder:mock-session-token@aiproxy.example.com"
    error_message = "proxy_auth_url should contain the mocked session token"
  }

  assert {
    condition     = output.cert_path == "/tmp/aibridge-proxy/ca-cert.pem"
    error_message = "cert_path output should match the default"
  }
}

run "test_aibridge_proxy_auth_url_http_with_port" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    proxy_url = "http://internal-proxy:8888"
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = output.proxy_auth_url == "http://coder:mock-session-token@internal-proxy:8888"
    error_message = "proxy_auth_url should preserve the port"
  }

  assert {
    condition     = output.cert_path == "/tmp/aibridge-proxy/ca-cert.pem"
    error_message = "cert_path output should match the default"
  }
}
