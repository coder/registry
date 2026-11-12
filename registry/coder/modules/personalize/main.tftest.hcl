mock_provider "coder" {}

variables {
  agent_id = "test-agent-id"
}

run "defaults" {
  command = plan

  assert {
    condition = (
      coder_script.personalize.agent_id == var.agent_id
      && coder_script.personalize.run_on_start
      && coder_script.personalize.start_blocks_login
      && coder_script.personalize.run_on_stop != true
      && coder_script.personalize_stop.agent_id == var.agent_id
      && coder_script.personalize_stop.run_on_stop
      && coder_script.personalize_stop.run_on_start != true
      && coder_script.personalize_stop.start_blocks_login != true
    )
    error_message = "Start must block login; stop must run only at stop, on the same agent."
  }

  assert {
    condition = (
      coder_script.personalize.log_path == "$HOME/.coder-modules/coder/personalize/logs/start.log"
      && coder_script.personalize_stop.log_path == "$HOME/.coder-modules/coder/personalize/logs/stop.log"
      && coder_env.log_dir.value == "$HOME/.coder-modules/coder/personalize/logs"
    )
    error_message = "Both logs must use the exported module log directory."
  }

  assert {
    condition = (
      coder_env.path.name == "CODER_MODULE_PERSONALIZE_PATH"
      && coder_env.path.value == "$HOME/personalize"
      && coder_env.dir.name == "CODER_MODULE_PERSONALIZE_DIR"
      && coder_env.dir.value == "$HOME/personalize.d"
      && coder_env.log_dir.name == "CODER_MODULE_PERSONALIZE_LOG_DIR"
    )
    error_message = "The default paths must be exported with an agent-expandable HOME."
  }
}

run "custom_path" {
  command = plan

  variables {
    path = "/tmp/personalize scripts/'`printf injected` [daily]*"
  }

  assert {
    condition = (
      strcontains(coder_script.personalize.script, base64encode(var.path))
      && strcontains(coder_script.personalize_stop.script, base64encode(var.path))
      && !strcontains(coder_script.personalize.script, var.path)
      && !strcontains(coder_script.personalize_stop.script, var.path)
    )
    error_message = "Both scripts must contain the encoded path, never the raw path."
  }

  assert {
    condition = (
      coder_env.path.value == var.path
      && coder_env.dir.value == "${var.path}.d"
    )
    error_message = "A path outside the home directory must be exported unchanged."
  }
}

run "reject_dollar_sign" {
  command = plan

  variables {
    path = "/tmp/$(printf injected)/personalize"
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
