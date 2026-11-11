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
    )
    error_message = "Both logs must use the module log directory."
  }

  assert {
    condition     = coder_env.personalize_path[0].name == "PERSONALIZE_PATH" && coder_env.personalize_path[0].value == "$HOME/personalize" && coder_env.personalize_path[0].agent_id == var.agent_id
    error_message = "The default path must be exported with an agent-expandable HOME."
  }
}

run "custom_path" {
  command = plan

  variables {
    path = "/tmp/personalize scripts/'$(printf injected) [daily]*"
  }

  assert {
    condition = alltrue([
      for script in [coder_script.personalize.script, coder_script.personalize_stop.script] :
      strcontains(script, base64encode(var.path)) && !strcontains(script, var.path)
    ])
    error_message = "Both scripts must contain the encoded path, never the raw path."
  }

  assert {
    condition     = length(coder_env.personalize_path) == 0
    error_message = "The agent must not expand dollar signs in the configured path."
  }
}

run "relative_path_environment" {
  command = plan

  variables {
    path = "personalize"
  }

  assert {
    condition     = coder_env.personalize_path[0].value == var.path
    error_message = "Paths without dollar signs must be exported unchanged."
  }
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
