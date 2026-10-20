override_data {
  target = data.coder_workspace.me
  values = {
    name       = "dev"
    access_url = "https://coder.example.com/"
  }
}

override_data {
  target = data.coder_workspace_owner.me
  values = {
    name = "alice"
  }
}

run "defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.module_directory == "$HOME/.coder-modules/coder-labs/kiro-crew"
    error_message = "module_directory must follow the $HOME/.coder-modules/<namespace>/<module> layout"
  }

  assert {
    condition     = resource.coder_app.kiro_crew.url == "http://localhost:8898/"
    error_message = "Visible app must point at the redirector on the default port"
  }

  assert {
    condition     = resource.coder_app.kiro_crew.slug == "kirocrew"
    error_message = "Visible app slug should default to 'kirocrew'"
  }

  assert {
    condition     = resource.coder_app.kiro_crew.subdomain == true
    error_message = "Visible app must be a subdomain app"
  }

  assert {
    condition     = resource.coder_app.kiro_crew_dashboard.url == "http://localhost:8899/"
    error_message = "Dashboard app must point at the gateway on the default port"
  }

  assert {
    condition     = resource.coder_app.kiro_crew_dashboard.slug == "kirocrew-dashboard"
    error_message = "Dashboard app slug should be '<slug>-dashboard'"
  }

  assert {
    condition     = resource.coder_app.kiro_crew_dashboard.hidden == true
    error_message = "Dashboard app must be hidden"
  }

  assert {
    condition     = resource.coder_app.kiro_crew_dashboard.subdomain == true
    error_message = "Dashboard app must be a subdomain app"
  }

  assert {
    condition     = local.dashboard_origin == "https://kirocrew-dashboard--dev--alice.coder.example.com"
    error_message = "Dashboard origin should be derived from the access URL, workspace, and owner"
  }

  assert {
    condition     = local.gateway_allowed_origins == local.dashboard_origin
    error_message = "Gateway allowlist should contain only the dashboard origin by default"
  }

  assert {
    condition     = output.kirocrew_url == "http://localhost:8899/"
    error_message = "kirocrew_url output should use the gateway port"
  }

  assert {
    condition     = length(resource.coder_env.aws_builder_id_token) == 0
    error_message = "No Builder ID env var should be created without a token"
  }

  assert {
    condition     = strcontains(local.start_script, "ARG_ALLOWED_ORIGINS=$(echo -n '${base64encode(local.dashboard_origin)}' | base64 -d)")
    error_message = "Start script should receive the allowlist base64 encoded"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_USE_CACHED='true'")
    error_message = "Install script should use cached binaries by default"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_EXTRA_MCP_JSON=$(echo -n '' | base64 -d)")
    error_message = "Install script should receive an empty extra MCP value by default"
  }
}

run "custom_ports_and_slug" {
  command = plan

  variables {
    agent_id      = "test-agent"
    port          = 19899
    redirect_port = 19898
    slug          = "crew"
  }

  assert {
    condition     = resource.coder_app.kiro_crew.url == "http://localhost:19898/"
    error_message = "Visible app must use redirect_port"
  }

  assert {
    condition     = resource.coder_app.kiro_crew_dashboard.slug == "crew-dashboard"
    error_message = "Dashboard app slug should follow the custom slug"
  }

  assert {
    condition     = local.dashboard_origin == "https://crew-dashboard--dev--alice.coder.example.com"
    error_message = "Dashboard origin should follow the custom slug"
  }

  assert {
    condition     = strcontains(local.start_script, "ARG_PORT='19899'") && strcontains(local.start_script, "ARG_REDIRECT_PORT='19898'")
    error_message = "Start script should receive the configured ports"
  }
}

run "healthchecks_use_configured_ports" {
  command = apply

  variables {
    agent_id      = "test-agent"
    port          = 19899
    redirect_port = 19898
  }

  assert {
    condition     = one([for h in resource.coder_app.kiro_crew.healthcheck : h.url]) == "http://localhost:19898/healthz"
    error_message = "Visible app healthcheck must use the redirector /healthz endpoint"
  }

  assert {
    condition     = one([for h in resource.coder_app.kiro_crew_dashboard.healthcheck : h.url]) == "http://localhost:19899/health"
    error_message = "Dashboard app healthcheck must use the gateway /health endpoint"
  }
}

run "allowed_origins_are_appended" {
  command = plan

  variables {
    agent_id        = "test-agent"
    allowed_origins = " https://coder.example.com,https://proxy.example.com "
  }

  assert {
    condition     = local.gateway_allowed_origins == "https://kirocrew-dashboard--dev--alice.coder.example.com,https://coder.example.com,https://proxy.example.com"
    error_message = "Extra allowed origins should follow the dashboard origin"
  }
}

run "dashboard_origin_override" {
  command = plan

  variables {
    agent_id         = "test-agent"
    dashboard_origin = "https://kirocrew-dashboard--dev--alice.apps.example.com"
  }

  assert {
    condition     = local.dashboard_origin == "https://kirocrew-dashboard--dev--alice.apps.example.com"
    error_message = "dashboard_origin should override the derived origin"
  }

  assert {
    condition     = output.dashboard_origin == "https://kirocrew-dashboard--dev--alice.apps.example.com"
    error_message = "dashboard_origin output should reflect the override"
  }
}

run "invalid_dashboard_origin_is_rejected" {
  command = plan

  variables {
    agent_id         = "test-agent"
    dashboard_origin = "https://apps.example.com/path"
  }

  expect_failures = [var.dashboard_origin]
}

run "invalid_extra_mcp_json_is_rejected" {
  command = plan

  variables {
    agent_id       = "test-agent"
    extra_mcp_json = "{not json"
  }

  expect_failures = [var.extra_mcp_json]
}

run "extra_mcp_json_is_base64_encoded" {
  command = plan

  variables {
    agent_id       = "test-agent"
    extra_mcp_json = "{\"mcpServers\":{\"demo\":{\"command\":\"echo\",\"args\":[\"it's\"]}}}"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("{\"mcpServers\":{\"demo\":{\"command\":\"echo\",\"args\":[\"it's\"]}}}"))
    error_message = "extra_mcp_json should be passed to the install script base64 encoded"
  }
}

run "http_access_url_keeps_scheme" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      name       = "dev"
      access_url = "http://localhost:3000"
    }
  }

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.dashboard_origin == "http://kirocrew-dashboard--dev--alice.localhost:3000"
    error_message = "Dashboard origin should keep the access URL scheme"
  }
}

run "builder_id_token_sets_env" {
  command = apply

  variables {
    agent_id             = "test-agent"
    aws_builder_id_token = "test-token"
  }

  assert {
    condition     = length(resource.coder_env.aws_builder_id_token) == 1
    error_message = "Builder ID env var should be created when a token is set"
  }

  assert {
    condition     = resource.coder_env.aws_builder_id_token[0].name == "KIRO_AWS_BUILDER_ID_TOKEN"
    error_message = "Builder ID token should be exported as KIRO_AWS_BUILDER_ID_TOKEN"
  }

  assert {
    condition     = !strcontains(local.install_script, "test-token") && !strcontains(local.start_script, "test-token")
    error_message = "Builder ID token must not be rendered into scripts"
  }
}

run "scripts_output_includes_start" {
  command = apply

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["coder-labs-kiro-crew-install_script", "coder-labs-kiro-crew-start_script"]
    error_message = "scripts output should list install and start scripts in run order"
  }
}

run "scripts_output_with_pre_and_post_install" {
  command = apply

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-kiro-crew-pre_install_script", "coder-labs-kiro-crew-install_script", "coder-labs-kiro-crew-post_install_script", "coder-labs-kiro-crew-start_script"]
    error_message = "scripts output should list every configured script in run order"
  }
}
