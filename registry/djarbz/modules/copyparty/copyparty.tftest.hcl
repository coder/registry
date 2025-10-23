# --- Test Case 1: Required Variables ---
run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }
}

# --- Test Case 2: Coder App URL uses custom port ---
run "app_url_uses_port" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    port     = 19999
  }

  assert {
    condition     = resource.coder_app.copyparty.url == "http://localhost:19999"
    error_message = "Expected copyparty app URL to include configured port"
  }
}

# --- Test Case 3: Default Values ---
run "test_defaults" {
  # This run block applies the module with default values
  # (except for the required 'agent_id' provided above).

  variables {
    agent_id = "example-agent-id"
  }

  # --- Asserts for coder_app "copyparty" ---
  assert {
    condition     = resource.coder_app.copyparty.display_name == "copyparty"
    error_message = "Default display_name is incorrect"
  }

  assert {
    condition     = resource.coder_app.copyparty.slug == "copyparty"
    error_message = "Default slug is incorrect"
  }

  assert {
    condition     = resource.coder_app.copyparty.url == "http://localhost:3923"
    error_message = "Default URL is incorrect, expected port 3923"
  }

  assert {
    condition     = resource.coder_app.copyparty.subdomain == false
    error_message = "Default subdomain should be false"
  }

  assert {
    condition     = resource.coder_app.copyparty.share == "owner"
    error_message = "Default share value should be 'owner'"
  }

  assert {
    condition     = resource.coder_app.copyparty.open_in == "slim-window"
    error_message = "Default open_in value should be 'slim-window'"
  }

  # --- Asserts for coder_script "copyparty" ---
  assert {
    condition     = coder_script.copyparty.display_name == "copyparty"
    error_message = "Script display_name is incorrect"
  }

  # Check rendered script content (this assumes your run.sh uses the variables)
  assert {
    condition     = strcontains(coder_script.copyparty.script, "PORT=\"3923\"")
    error_message = "Script content does not reflect default port"
  }

  assert {
    condition     = strcontains(coder_script.copyparty.script, "LOG_PATH=\"/tmp/copyparty.log\"")
    error_message = "Script content does not reflect default log_path"
  }

  assert {
    condition     = strcontains(coder_script.copyparty.script, "IFS=',' read -r -a ARGUMENTS \u003c\u003c\u003c \"\"")
    error_message = "Script content does not reflect default empty arguments"
  }
}

# --- Test Case 4: Custom Values ---
run "test_custom_values" {
  # Override default variables for this specific run
  variables {
    agent_id       = "example-agent-id"
    port           = 8080
    slug           = "my-custom-app"
    display_name   = "My Custom App"
    share          = "authenticated"
    open_in        = "tab"
    pinned_version = "v1.2.3"
    arguments      = ["--verbose", "-v"]
    log_path       = "/var/log/custom.log"
  }

  # --- Asserts for coder_app "copyparty" ---
  assert {
    condition     = resource.coder_app.copyparty.display_name == "My Custom App"
    error_message = "Custom display_name was not applied"
  }

  assert {
    condition     = resource.coder_app.copyparty.slug == "my-custom-app"
    error_message = "Custom slug was not applied"
  }

  assert {
    condition     = resource.coder_app.copyparty.url == "http://localhost:8080"
    error_message = "Custom port was not applied to URL"
  }

  assert {
    condition     = resource.coder_app.copyparty.share == "authenticated"
    error_message = "Custom share value was not applied"
  }

  assert {
    condition     = resource.coder_app.copyparty.open_in == "tab"
    error_message = "Custom open_in value was not applied"
  }

  # --- Asserts for coder_script "copyparty" ---
  assert {
    condition     = strcontains(coder_script.copyparty.script, "PORT=\"8080\"")
    error_message = "Script content does not reflect custom port"
  }

  assert {
    condition     = strcontains(coder_script.copyparty.script, "PINNED_VERSION=\"v1.2.3\"")
    error_message = "Script content does not reflect custom pinned_version"
  }

  assert {
    condition     = strcontains(coder_script.copyparty.script, "IFS=',' read -r -a ARGUMENTS \u003c\u003c\u003c \"--verbose,-v\"")
    error_message = "Script content does not reflect custom arguments"
  }

  assert {
    condition     = strcontains(coder_script.copyparty.script, "LOG_PATH=\"/var/log/custom.log\"")
    error_message = "Script content does not reflect custom log_path"
  }
}

# --- Test Case 5: Validation Failure (open_in) ---
run "test_invalid_open_in" {
  # This is a 'plan' test that expects a failure
  command = plan

  variables {
    agent_id = "example-agent-id"
    open_in  = "invalid-value"
  }

  # Expect this plan to fail due to the validation rule in 'var.open_in'
  expect_failures = [
    var.open_in,
  ]
}

# --- Test Case 6: Validation Failure (share) ---
run "test_invalid_share" {
  # This is a 'plan' test that expects a failure
  command = plan

  variables {
    agent_id = "example-agent-id"
    share    = "everyone" # This is not 'owner', 'authenticated', or 'public'
  }

  # Expect this plan to fail due to the validation rule in 'var.share'
  expect_failures = [
    var.share,
  ]
}
