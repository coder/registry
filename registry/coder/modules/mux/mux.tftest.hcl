run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "install_false_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
    install    = false
  }

  expect_failures = [
    resource.coder_script.mux
  ]
}

# Needs command = apply because the URL contains random_password.result,
# which is unknown during plan.
run "custom_port" {
  command = apply

  variables {
    agent_id = "foo"
    port     = 8080
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:8080?token=")
    error_message = "coder_app URL must use the configured port and include auth token"
  }

  assert {
    condition     = trimprefix(resource.coder_app.mux.url, "http://localhost:8080?token=") == random_password.mux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

# Needs command = apply because random_password.result is unknown during plan.
run "auth_token_in_server_script" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "MUX_SERVER_AUTH_TOKEN=")
    error_message = "mux launch script must set MUX_SERVER_AUTH_TOKEN"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, random_password.mux_auth_token.result)
    error_message = "mux launch script must use the generated auth token"
  }
}

# Needs command = apply because random_password.result is unknown during plan.
run "auth_token_in_url" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:4000?token=")
    error_message = "coder_app URL must include auth token query parameter"
  }

  assert {
    condition     = trimprefix(resource.coder_app.mux.url, "http://localhost:4000?token=") == random_password.mux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

run "custom_version" {
  command = plan

  variables {
    agent_id        = "foo"
    install_version = "0.3.0"
  }
}

# install=false should succeed
run "install_false_only_success" {
  command = plan

  variables {
    agent_id = "foo"
    install  = false
  }
}

# use_cached-only should succeed
run "use_cached_only_success" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
  }
}
