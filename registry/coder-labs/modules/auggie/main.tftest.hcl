run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_auggie == true
    error_message = "install_auggie should default to true"
  }

  assert {
    condition     = var.auggie_version == ""
    error_message = "auggie_version should default to empty (latest)"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/auggie"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/auggie'"
  }

  assert {
    condition     = length(coder_env.auggie_session_auth) == 0
    error_message = "AUGMENT_SESSION_AUTH should not be created when augment_session_token is empty"
  }
}

run "workdir_trailing_slash_is_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should have its trailing slash trimmed"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("/home/coder/project"))
    error_message = "install script should receive the base64-encoded workdir"
  }
}

run "session_token_creates_env_var" {
  command = plan

  variables {
    agent_id              = "test-agent"
    augment_session_token = "{\"accessToken\":\"test-secret-token\",\"tenantURL\":\"https://d1.api.augmentcode.com/\"}"
  }

  assert {
    condition     = coder_env.auggie_session_auth[0].name == "AUGMENT_SESSION_AUTH" && coder_env.auggie_session_auth[0].value == var.augment_session_token
    error_message = "AUGMENT_SESSION_AUTH should be set to augment_session_token"
  }

  assert {
    condition     = !strcontains(local.install_script, "test-secret-token") && !strcontains(local.install_script, base64encode(nonsensitive(var.augment_session_token)))
    error_message = "augment_session_token should not be rendered into the install script"
  }
}

run "inputs_are_encoded" {
  command = plan

  variables {
    agent_id       = "test-agent"
    auggie_version = "0.35.0"
    auggie_model   = "sonnet4.5"
    rules          = "# Rules\n- Be concise"
    mcp            = "{\"mcpServers\": {\"filesystem\": {\"command\": \"npx\", \"args\": [\"-y\", \"@modelcontextprotocol/server-filesystem\"]}}}"
    mcp_files      = ["/home/coder/mcp.json"]
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("0.35.0"))
    error_message = "install script should receive the base64-encoded version"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("sonnet4.5"))
    error_message = "install script should receive the base64-encoded model"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(var.rules))
    error_message = "install script should receive the base64-encoded rules"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(var.mcp))
    error_message = "install script should receive the base64-encoded mcp"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(jsonencode(var.mcp_files)))
    error_message = "install script should receive the base64-encoded mcp_files"
  }
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-auggie-pre_install_script", "coder-labs-auggie-install_script", "coder-labs-auggie-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["coder-labs-auggie-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
