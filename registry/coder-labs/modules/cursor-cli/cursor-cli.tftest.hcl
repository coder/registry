// Terraform tests for the cursor-cli module
// Validates that we render expected script content given inputs

run "defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
    folder   = "/home/coder"
  }

  assert {
    condition     = can(regex("Cursor CLI", resource.coder_script.cursor_cli.display_name))
    error_message = "Expected coder_script to be created"
  }
}

run "non_interactive_mode" {
  command = plan

  variables {
    agent_id      = "test-agent"
    folder        = "/home/coder"
    output_format = "json"
  }

  assert {
    // non-interactive always prints; output format propagates
    condition     = can(regex("OUTPUT_FORMAT='json'", resource.coder_script.cursor_cli.script))
    error_message = "Expected OUTPUT_FORMAT to be propagated"
  }
}

run "model_and_force" {
  command = plan

  variables {
    agent_id = "test-agent"
    folder   = "/home/coder"
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
    agent_id = "test-agent"
    folder   = "/home/coder"
    mcp_json = jsonencode({ mcpServers = { foo = { command = "foo", type = "stdio" } } })
    rules_files = {
      "global.yml" = "version: 1\nrules:\n  - name: global\n    include: ['**/*']\n    description: global rule"
    }
    pre_install_script  = "#!/bin/bash\necho pre-install"
    post_install_script = "#!/bin/bash\necho post-install"
  }

  // Ensure project mcp_json is passed
  assert {
    condition     = can(regex(base64encode(jsonencode({ mcpServers = { foo = { command = "foo", type = "stdio" } } })), resource.coder_script.cursor_cli.script))
    error_message = "Expected PROJECT_MCP_JSON (base64) to be in the install step"
  }

  // Ensure rules map is passed
  assert {
    condition     = can(regex(base64encode(jsonencode({ "global.yml" : "version: 1\nrules:\n  - name: global\n    include: ['**/*']\n    description: global rule" })), resource.coder_script.cursor_cli.script))
    error_message = "Expected PROJECT_RULES_JSON (base64) to be in the install step"
  }

  // Ensure pre/post install scripts are embedded
  assert {
    condition     = can(regex(base64encode("#!/bin/bash\necho pre-install"), resource.coder_script.cursor_cli.script))
    error_message = "Expected pre-install script to be embedded"
  }
  assert {
    condition     = can(regex(base64encode("#!/bin/bash\necho post-install"), resource.coder_script.cursor_cli.script))
    error_message = "Expected post-install script to be embedded"
  }
}

run "api_key_env_var" {
  command = plan

  variables {
    agent_id = "test-agent"
    folder   = "/home/coder"
    api_key  = "sk-test-123"
  }

  assert {
    condition     = resource.coder_env.cursor_api_key[0].name == "CURSOR_API_KEY"
    error_message = "Expected CURSOR_API_KEY env to be created when api_key is set"
  }

  assert {
    condition     = resource.coder_env.cursor_api_key[0].value == "sk-test-123"
    error_message = "Expected CURSOR_API_KEY env value to be set from api_key"
  }
}
