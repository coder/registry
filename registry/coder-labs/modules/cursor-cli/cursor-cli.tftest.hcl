// Terraform tests for the cursor-cli module
// Validates that we render expected script content given inputs

run "defaults_noninteractive" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = can(regex("Cursor CLI", resource.coder_script.cursor_cli.display_name))
    error_message = "Expected coder_script to be created"
  }
}

run "non_interactive_mode" {
  command = plan

  variables {
    agent_id         = "test-agent"
    output_format    = "json"
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
    agent_id   = "test-agent"
    mcp_json   = jsonencode({ mcpServers = { foo = { command = "foo", type = "stdio" } } })
    rules_files = {
      "global.yml" = "version: 1\nrules:\n  - name: global\n    include: ['**/*']\n    description: global rule"
    }
  }

  // Ensure project mcp_json is passed
  assert {
    condition     = can(regex(base64encode(jsonencode({ mcpServers = { foo = { command = "foo", type = "stdio" } } })), resource.coder_script.cursor_cli.script))
    error_message = "Expected PROJECT_MCP_JSON (base64) to be in the install step"
  }

  // Ensure rules map is passed
  assert {
    condition     = can(regex(base64encode(jsonencode({"global.yml":"version: 1\nrules:\n  - name: global\n    include: ['**/*']\n    description: global rule"})), resource.coder_script.cursor_cli.script))
    error_message = "Expected PROJECT_RULES_JSON (base64) to be in the install step"
  }
}

run "output_api_key" {
  command = plan

  variables {
    agent_id        = "test-agent"
    output_format   = "json"
    api_key         = "sk-test-123"
  }

  assert {
    condition     = can(regex("OUTPUT_FORMAT='json'", resource.coder_script.cursor_cli.script))
    error_message = "Expected output format to be passed"
  }

  assert {
    condition     = can(regex("API_KEY_SECRET='sk-test-123'", resource.coder_script.cursor_cli.script))
    error_message = "Expected API key to be plumbed (to CURSOR_API_KEY at runtime)"
  }
}
