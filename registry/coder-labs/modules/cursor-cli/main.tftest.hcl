run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_cursor_cli == true
    error_message = "install_cursor_cli should default to true"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/cursor-cli"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/cursor-cli'"
  }

  assert {
    condition     = length(coder_env.cursor_api_key) == 0
    error_message = "CURSOR_API_KEY should not be created when api_key is empty"
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
}

run "api_key_creates_env_var" {
  command = plan

  variables {
    agent_id = "test-agent"
    api_key  = "test-cursor-key"
  }

  assert {
    condition     = coder_env.cursor_api_key[0].name == "CURSOR_API_KEY" && coder_env.cursor_api_key[0].value == "test-cursor-key"
    error_message = "CURSOR_API_KEY env var should be created with the provided key"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.api_key)) && !strcontains(local.install_script, base64encode(nonsensitive(var.api_key)))
    error_message = "API key should not be rendered into the install script"
  }
}

run "invalid_mcp_fails" {
  command = plan

  variables {
    agent_id = "test-agent"
    mcp      = "{\"servers\": {}}"
  }

  expect_failures = [
    var.mcp,
  ]
}

run "rules_files_require_workdir" {
  command = plan

  variables {
    agent_id = "test-agent"
    rules_files = {
      "general.mdc" = "Write clean code"
    }
  }

  expect_failures = [
    var.rules_files,
  ]
}

run "rules_files_reject_paths" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
    rules_files = {
      "../escape.mdc" = "nope"
    }
  }

  expect_failures = [
    var.rules_files,
  ]
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = length(output.scripts) == 3
    error_message = "scripts output should list pre_install, install, and post_install"
  }

  assert {
    condition     = output.scripts == ["coder-labs-cursor-cli-pre_install_script", "coder-labs-cursor-cli-install_script", "coder-labs-cursor-cli-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["coder-labs-cursor-cli-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
