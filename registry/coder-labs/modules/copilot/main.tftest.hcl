run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.copilot_model == "claude-sonnet-4.5"
    error_message = "Default model should be 'claude-sonnet-4.5'"
  }

  assert {
    condition     = var.install_copilot == true
    error_message = "install_copilot should default to true"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/copilot"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/copilot'"
  }
}

run "github_token_creates_env_vars" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = "test_github_token_abc123"
  }

  assert {
    condition     = coder_env.github_token[0].name == "GITHUB_TOKEN" && coder_env.github_token[0].value == "test_github_token_abc123"
    error_message = "GITHUB_TOKEN env var should be created with the provided token"
  }

  assert {
    condition     = coder_env.gh_token[0].name == "GH_TOKEN" && coder_env.gh_token[0].value == "test_github_token_abc123"
    error_message = "GH_TOKEN env var should be created with the provided token"
  }
}

run "github_token_not_created_when_empty" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = ""
  }

  assert {
    condition     = length(coder_env.github_token) == 0 && length(coder_env.gh_token) == 0
    error_message = "GitHub token env vars should not be created when empty"
  }
}

run "copilot_model_env_var_uses_given_model" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4"
  }

  assert {
    condition     = coder_env.copilot_model[0].name == "COPILOT_MODEL" && coder_env.copilot_model[0].value == "claude-sonnet-4"
    error_message = "COPILOT_MODEL env var should be created with the given model"
  }
}

run "copilot_model_env_var_is_always_set" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4.5"
  }

  assert {
    condition     = coder_env.copilot_model[0].name == "COPILOT_MODEL" && coder_env.copilot_model[0].value == "claude-sonnet-4.5"
    error_message = "COPILOT_MODEL env var should be set to the model as given, including the default"
  }
}

run "copilot_config_merges_with_trusted_directories" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder/project/"
    trusted_directories = ["/workspace", "/data"]
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should be trimmed of trailing slash"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/home/coder/project")
    error_message = "workdir should be included in trusted folders"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/workspace") && contains(jsondecode(local.final_copilot_config).trusted_folders, "/data")
    error_message = "trusted_directories should be merged into config"
  }
}

run "custom_copilot_config_overrides_default" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
    copilot_config = jsonencode({
      banner          = "always"
      theme           = "dark"
      trusted_folders = ["/custom"]
    })
  }

  assert {
    condition     = jsondecode(local.final_copilot_config).banner == "always" && jsondecode(local.final_copilot_config).theme == "dark"
    error_message = "Custom banner and theme settings should be applied"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/custom")
    error_message = "Custom trusted folder should be preserved"
  }
}

run "workdir_optional" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should default to an empty string"
  }

  assert {
    condition     = length(output.scripts) == 1
    error_message = "scripts output should have the install script even without a workdir"
  }
}

run "script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = output.scripts == ["coder-labs-copilot-install_script"]
    error_message = "scripts output should list only the install script when pre/post are not configured"
  }
}

run "script_outputs_with_pre_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-copilot-pre_install_script", "coder-labs-copilot-install_script", "coder-labs-copilot-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}
