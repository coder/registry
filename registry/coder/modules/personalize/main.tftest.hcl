mock_provider "coder" {}

variables {
  agent_id = "test-agent-id"
}

run "defaults" {
  command = plan

  assert {
    condition     = coder_script.personalize.agent_id == var.agent_id && coder_script.personalize_stop.agent_id == var.agent_id
    error_message = "Both scripts must use the configured agent ID."
  }

  assert {
    condition     = coder_script.personalize.run_on_start && coder_script.personalize.start_blocks_login && coder_script.personalize.run_on_stop != true
    error_message = "Personalize must block login at start and must not run at stop."
  }

  assert {
    condition     = coder_script.personalize_stop.run_on_stop && coder_script.personalize_stop.run_on_start != true && coder_script.personalize_stop.start_blocks_login != true
    error_message = "The stop script must run only at stop and must not block login."
  }

  assert {
    condition     = coder_script.personalize.log_path == "$HOME/.coder-modules/coder/personalize/logs/start.log" && coder_script.personalize_stop.log_path == "$HOME/.coder-modules/coder/personalize/logs/stop.log"
    error_message = "Both logs must use the module log directory."
  }

  assert {
    condition     = length(coder_env.personalize_path) == 1 && coder_env.personalize_path[0].name == "PERSONALIZE_PATH" && coder_env.personalize_path[0].value == "$HOME/personalize" && coder_env.personalize_path[0].agent_id == var.agent_id
    error_message = "The default path must be exported with an agent-expandable HOME."
  }
}

run "custom_paths" {
  command = plan

  variables {
    path = "/tmp/personalize scripts/'$(printf injected) [daily]*"
  }

  assert {
    condition     = strcontains(coder_script.personalize.script, base64encode(var.path)) && strcontains(coder_script.personalize_stop.script, base64encode(var.path))
    error_message = "Both scripts must contain the base64-encoded custom path."
  }

  assert {
    condition     = !strcontains(coder_script.personalize.script, var.path) && !strcontains(coder_script.personalize_stop.script, var.path)
    error_message = "Neither script may interpolate the raw custom path."
  }

  assert {
    condition     = length(coder_env.personalize_path) == 0
    error_message = "Paths containing a dollar sign cannot be exported faithfully by the agent."
  }
}

run "absolute_path_environment" {
  command = plan

  variables {
    path = "/opt/personalize workspace"
  }

  assert {
    condition     = coder_env.personalize_path[0].value == var.path
    error_message = "Absolute paths must be exported unchanged."
  }
}

run "relative_path_environment" {
  command = plan

  variables {
    path = "personalize"
  }

  assert {
    condition     = length(coder_env.personalize_path) == 0
    error_message = "Relative paths must use the absolute path in the config file, not an environment value."
  }
}

run "named_home_environment" {
  command = plan

  variables {
    path = "~someone/personalize"
  }

  assert {
    condition     = length(coder_env.personalize_path) == 0
    error_message = "Named-user home paths cannot be exported as absolute paths."
  }
}

run "reject_empty" {
  command = plan

  variables {
    path = ""
  }

  expect_failures = [var.path]
}

run "reject_whitespace_only" {
  command = plan

  variables {
    path = " \t "
  }

  expect_failures = [var.path]
}

run "reject_current_directory" {
  command = plan

  variables {
    path = "."
  }

  expect_failures = [var.path]
}

run "reject_parent_directory" {
  command = plan

  variables {
    path = ".."
  }

  expect_failures = [var.path]
}

run "reject_trailing_current_directory" {
  command = plan

  variables {
    path = "/tmp/personalize/."
  }

  expect_failures = [var.path]
}

run "reject_trailing_parent_directory" {
  command = plan

  variables {
    path = "~/personalize/.."
  }

  expect_failures = [var.path]
}

run "reject_bare_home" {
  command = plan

  variables {
    path = "~"
  }

  expect_failures = [var.path]
}

run "reject_trailing_slash" {
  command = plan

  variables {
    path = "/tmp/personalize/"
  }

  expect_failures = [var.path]
}

run "reject_newline" {
  command = plan

  variables {
    path = "~/personalize\ninjected"
  }

  expect_failures = [var.path]
}

run "reject_carriage_return" {
  command = plan

  variables {
    path = "~/personalize\rinjected"
  }

  expect_failures = [var.path]
}
