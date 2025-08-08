// Terraform tests for the cursor-cli module
// Validates that we render expected script content given inputs

run "defaults_interactive" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = can(regex("INTERACTIVE='true'", resource.coder_script.cursor_cli.script))
    error_message = "Expected INTERACTIVE default to be true"
  }

  assert {
    condition     = can(regex("BINARY_NAME='cursor-agent'", resource.coder_script.cursor_cli.script))
    error_message = "Expected default binary_name to be cursor-agent"
  }
}

run "non_interactive_mode" {
  command = plan

  variables {
    agent_id            = "test-agent"
    interactive         = false
    non_interactive_cmd = "run --once"
  }

  assert {
    condition     = can(regex("INTERACTIVE='false'", resource.coder_script.cursor_cli.script))
    error_message = "Expected INTERACTIVE to be false when interactive=false"
  }

  assert {
    condition     = can(regex("NON_INTERACTIVE_CMD='run --once'", resource.coder_script.cursor_cli.script))
    error_message = "Expected NON_INTERACTIVE_CMD to be propagated"
  }
}

run "model_and_force" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "test-model"
    force    = true
  }

  assert {
    condition     = can(regex("MODEL='test-model'", resource.coder_script.cursor_cli.script))
    error_message = "Expected MODEL to be propagated"
  }

  assert {
    condition     = can(regex("FORCE='true'", resource.coder_script.cursor_cli.script))
    error_message = "Expected FORCE true to be propagated"
  }
}

run "additional_settings_propagated" {
  command = plan

  variables {
    agent_id            = "test-agent"
    additional_settings = jsonencode({
      mcpServers = {
        coder = {
          command = "coder"
          args    = ["exp", "mcp", "server"]
          type    = "stdio"
        }
      }
    })
  }

  // Ensure the encoded settings are passed into the install invocation
  assert {
    condition     = can(regex(base64encode(jsonencode({
      mcpServers = {
        coder = {
          command = "coder"
          args    = ["exp", "mcp", "server"]
          type    = "stdio"
        }
      }
    })), resource.coder_script.cursor_cli.script))
    error_message = "Expected ADDITIONAL_SETTINGS (base64) to be in the install step"
  }
}
