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

run "custom_port" {
  command = plan

  variables {
    agent_id = "foo"
    port     = 8080
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:8080?token=")
    error_message = "coder_app URL must use the configured port and include auth token"
  }
}

run "auth_token_in_env" {
  command = plan

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = resource.coder_env.mux_auth_token.name == "MUX_SERVER_AUTH_TOKEN"
    error_message = "MUX_SERVER_AUTH_TOKEN env var must be set"
  }

  assert {
    condition     = length(resource.coder_env.mux_auth_token.value) == 64
    error_message = "Auth token must be 64 characters"
  }
}

run "auth_token_in_url" {
  command = plan

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:4000?token=")
    error_message = "coder_app URL must include auth token query parameter"
  }

  assert {
    condition     = resource.coder_env.mux_auth_token.value == random_password.mux_auth_token.result
    error_message = "env var and URL token must use the same generated secret"
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
