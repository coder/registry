run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.port == 6767
    error_message = "port should default to 6767"
  }

  assert {
    condition     = var.share == "owner"
    error_message = "share should default to owner"
  }

  assert {
    condition     = var.omnigent_version == "latest"
    error_message = "omnigent_version should default to latest"
  }

  assert {
    condition     = var.icon == "/icon/omnigent.svg"
    error_message = "icon should default to the Coder runtime icon path"
  }

  assert {
    condition     = coder_app.omnigent.icon == "/icon/omnigent.svg"
    error_message = "coder_app icon should use the default runtime icon path"
  }

  assert {
    condition     = coder_app.omnigent.url == "http://localhost:6767"
    error_message = "coder_app url should use default port 6767"
  }

  assert {
    condition     = coder_app.omnigent.share == "owner"
    error_message = "coder_app share should default to owner"
  }
}

run "test_custom_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 8080
  }

  assert {
    condition     = var.port == 8080
    error_message = "port should be set to 8080"
  }

  assert {
    condition     = coder_app.omnigent.url == "http://localhost:8080"
    error_message = "coder_app url should use custom port 8080"
  }
}

run "test_allowed_origins" {
  command = plan

  variables {
    agent_id        = "test-agent"
    allowed_origins = ["https://omnigent--workspace--owner--apps.example.com"]
  }

  assert {
    condition     = contains(var.allowed_origins, "https://omnigent--workspace--owner--apps.example.com")
    error_message = "allowed_origins should include the configured origin"
  }

  assert {
    condition     = strcontains(local.start_script, "OMNIGENT_WS_ALLOWED_ORIGINS")
    error_message = "start script should export Omnigent's trusted origin allowlist"
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("https://omnigent--workspace--owner--apps.example.com"))
    error_message = "start script should include the encoded configured origin"
  }

  assert {
    condition     = strcontains(local.start_script, "CODER_AGENT_URL")
    error_message = "start script should allow the path-based Coder app origin"
  }

  assert {
    condition     = strcontains(local.start_script, "VSCODE_PROXY_URI")
    error_message = "start script should derive Coder app origins from VSCODE_PROXY_URI"
  }

  assert {
    condition     = strcontains(local.start_script, "omnigent--")
    error_message = "start script should allow the named Omnigent Coder app origin"
  }
}

run "test_invalid_allowed_origin_path" {
  command = plan

  variables {
    agent_id        = "test-agent"
    allowed_origins = ["https://omnigent.example.com/path"]
  }

  expect_failures = [var.allowed_origins]
}

run "test_custom_share" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "authenticated"
  }

  assert {
    condition     = var.share == "authenticated"
    error_message = "share should be set to authenticated"
  }

  assert {
    condition     = coder_app.omnigent.share == "authenticated"
    error_message = "coder_app share should be authenticated"
  }
}

run "test_custom_version" {
  command = plan

  variables {
    agent_id         = "test-agent"
    omnigent_version = "0.1.0"
  }

  assert {
    condition     = var.omnigent_version == "0.1.0"
    error_message = "omnigent_version should be set to 0.1.0"
  }
}

run "test_scripts_output" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(output.scripts) > 0
    error_message = "scripts output should be non-empty"
  }
}

run "test_install_script_installs_uv" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.install_script, "https://astral.sh/uv/install.sh")
    error_message = "install script should install uv when it is missing"
  }

  assert {
    condition     = strcontains(local.install_script, "command -v uv")
    error_message = "install script should check whether uv is available"
  }
}

run "test_install_script_clears_stale_agents" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.install_script, "rm -f \"$${ARG_AGENTS_DIR}\"/*.yaml")
    error_message = "install script should clear stale generated agent YAML files"
  }
}

run "test_start_script_backgrounds_host" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.start_script, "nohup omnigent host")
    error_message = "start script should run the Omnigent host in the background"
  }

  assert {
    condition     = strcontains(local.start_script, "host.log")
    error_message = "start script should write Omnigent host logs to host.log"
  }
}

run "test_start_script_quotes_server_flags" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.start_script, "SERVER_FLAGS=(")
    error_message = "start script should build server flags as a bash array"
  }

  assert {
    condition     = strcontains(local.start_script, "omnigent server \"$${SERVER_FLAGS[@]}\"")
    error_message = "start script should pass server flags without word splitting"
  }
}

run "test_start_script_connects_host_to_app_server" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.start_script, "omnigent host --server")
    error_message = "start script should connect the host to the Coder app server"
  }

  assert {
    condition     = strcontains(local.start_script, "http://localhost:$${ARG_PORT}")
    error_message = "start script should pass the configured Omnigent server port to the host"
  }
}

run "test_start_script_passes_ai_gateway_token_to_runners" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = strcontains(local.start_script, "append_runner_env_passthrough")
    error_message = "start script should append runner env passthrough entries"
  }

  assert {
    condition     = strcontains(local.start_script, "OPENAI_CODER_AIGATEWAY_SESSION_TOKEN")
    error_message = "start script should pass the Coder AI Gateway OpenAI token to Omnigent runners"
  }

  assert {
    condition     = strcontains(local.start_script, "OMNIGENT_RUNNER_ENV_PASSTHROUGH=\"$${OMNIGENT_RUNNER_ENV_PASSTHROUGH},$${name}\"")
    error_message = "start script should preserve existing runner env passthrough values"
  }

  assert {
    condition     = strcontains(local.start_script, "*\",$${name},\"*) ;;")
    error_message = "start script should avoid duplicate runner env passthrough entries"
  }
}

run "test_port_output" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 7777
  }

  assert {
    condition     = output.port == 7777
    error_message = "port output should match the configured port"
  }
}

run "test_invalid_port_low" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 80
  }

  expect_failures = [var.port]
}

run "test_invalid_port_high" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 65536
  }

  expect_failures = [var.port]
}

run "test_invalid_share" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "invalid"
  }

  expect_failures = [var.share]
}

run "test_server_config" {
  command = plan

  variables {
    agent_id      = "test-agent"
    server_config = "policies: {}"
  }

  assert {
    condition     = var.server_config == "policies: {}"
    error_message = "server_config should be set"
  }
}

run "test_server_config_path" {
  command = plan

  variables {
    agent_id           = "test-agent"
    server_config_path = "/home/coder/.omnigent/server.yaml"
  }

  assert {
    condition     = output.server_config_path == "/home/coder/.omnigent/server.yaml"
    error_message = "server_config_path output should match the provided path"
  }
}

run "test_server_config_mutual_exclusion" {
  command = plan

  variables {
    agent_id           = "test-agent"
    server_config      = "policies: {}"
    server_config_path = "/home/coder/.omnigent/server.yaml"
  }

  expect_failures = [var.server_config]
}

run "test_invalid_agent_name" {
  command = plan

  variables {
    agent_id = "test-agent"
    agents = [
      {
        name    = "bad\tname"
        content = "name: reviewer\ninstructions: You are a reviewer."
      }
    ]
  }

  expect_failures = [var.agents]
}

run "test_agents" {
  command = plan

  variables {
    agent_id = "test-agent"
    agents = [
      {
        name    = "reviewer"
        content = "name: reviewer\ninstructions: You are a reviewer."
      }
    ]
  }

  assert {
    condition     = length(var.agents) == 1
    error_message = "agents should have one entry"
  }
}
