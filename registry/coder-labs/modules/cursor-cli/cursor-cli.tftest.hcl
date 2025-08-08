// Terraform tests for the cursor-cli module
// Validates that we render expected script content given inputs

run "defaults_noninteractive" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = can(regex("BINARY_NAME='cursor-agent'", resource.coder_script.cursor_cli.script))
    error_message = "Expected default binary_name to be cursor-agent"
  }
}

run "non_interactive_mode" {
  command = plan

  variables {
    agent_id         = "test-agent"
    base_command     = "status"
    extra_args       = ["--dry-run"]
    output_format    = "json"
  }

  assert {
    // base command and -p --output-format json are included in env
    condition     = can(regex("BASE_COMMAND='status'", resource.coder_script.cursor_cli.script))
    error_message = "Expected BASE_COMMAND to be propagated"
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
    mcp_json   = jsonencode({ mcpServers = { foo = { command = "foo", type = "stdio" } } })
    rules_files = {
      "global.yml" = "version: 1\nrules:\n  - name: global\n    include: ['**/*']\n    description: global rule"
    }
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

run "output_api_key_binary_basecmd_extra" {
  command = plan

  variables {
    agent_id        = "test-agent"
    output_format   = "json"
    api_key         = "sk-test-123"
    binary_name     = "cursor-agent"
    base_command    = "status"
    extra_args      = ["--foo", "bar"]
  }

  assert {
    condition     = can(regex("OUTPUT_FORMAT='json'", resource.coder_script.cursor_cli.script))
    error_message = "Expected output format to be passed"
  }

  assert {
    condition     = can(regex("API_KEY_SECRET='sk-test-123'", resource.coder_script.cursor_cli.script))
    error_message = "Expected API key to be plumbed (to CURSOR_API_KEY at runtime)"
  }

  assert {
    condition     = can(regex("BINARY_NAME='cursor-agent'", resource.coder_script.cursor_cli.script))
    error_message = "Expected binary name to be forwarded"
  }

  assert {
    condition     = can(regex("BASE_COMMAND='status'", resource.coder_script.cursor_cli.script))
    error_message = "Expected base command to be forwarded"
  }

  assert {
    condition     = can(regex(base64encode("--foo\nbar"), resource.coder_script.cursor_cli.script))
    error_message = "Expected extra args to be base64 encoded and passed"
  }
}
