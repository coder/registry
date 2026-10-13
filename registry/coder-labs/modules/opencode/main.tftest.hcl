run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_opencode == true
    error_message = "install_opencode should default to true"
  }

  assert {
    condition     = var.opencode_version == "latest"
    error_message = "opencode_version should default to 'latest'"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/opencode"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/opencode'"
  }

  assert {
    condition     = length(coder_env.opencode_auth_json) == 0
    error_message = "CODER_OPENCODE_AUTH_JSON should not be created when auth_json is empty"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("latest"))
    error_message = "install script should receive the opencode version"
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

run "auth_json_creates_env_var" {
  command = plan

  variables {
    agent_id  = "test-agent"
    auth_json = "[{\"id\": \"coder-anthropic\", \"integrationID\": \"anthropic\", \"label\": \"coder\", \"active\": true, \"value\": {\"type\": \"key\", \"key\": \"sk-ant-test-secret\"}}]"
  }

  assert {
    condition     = coder_env.opencode_auth_json[0].name == "CODER_OPENCODE_AUTH_JSON" && coder_env.opencode_auth_json[0].value == var.auth_json
    error_message = "CODER_OPENCODE_AUTH_JSON env var should be created with the provided auth_json"
  }

  assert {
    condition     = !strcontains(local.install_script, "sk-ant-test-secret") && !strcontains(local.install_script, base64encode(nonsensitive(var.auth_json)))
    error_message = "auth_json should not be rendered into the install script"
  }
}

run "mcp_is_encoded" {
  command = plan

  variables {
    agent_id = "test-agent"
    mcp      = "{\"playwright\": {\"type\": \"local\", \"command\": [\"npx\", \"-y\", \"@playwright/mcp\"]}}"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(var.mcp))
    error_message = "install script should receive the base64-encoded mcp"
  }
}

run "pinned_opencode_version_is_accepted" {
  command = plan

  variables {
    agent_id         = "test-agent"
    opencode_version = "v2.0.27"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("v2.0.27"))
    error_message = "install script should receive the pinned opencode version"
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
    condition     = output.scripts == ["coder-labs-opencode-pre_install_script", "coder-labs-opencode-install_script", "coder-labs-opencode-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["coder-labs-opencode-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
