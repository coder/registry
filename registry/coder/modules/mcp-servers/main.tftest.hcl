run "plan_with_required_variables" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["claude code", "codex"]
  }

  assert {
    condition     = data.coder_parameter.mcp_servers.type == "list(string)"
    error_message = "MCP server selection must use a list(string) parameter."
  }

  assert {
    condition     = data.coder_parameter.mcp_servers.form_type == "multi-select"
    error_message = "MCP server selection must render as a multi-select field."
  }
}

run "uses_selected_defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["gemini"]
    default  = ["github", "playwright"]
  }

  assert {
    condition     = data.coder_parameter.mcp_servers.default == jsonencode(["github", "playwright"])
    error_message = "Selected defaults must be encoded deterministically."
  }

  assert {
    condition     = data.coder_parameter.mcp_servers.mutable == false
    error_message = "MCP selections must remain immutable because deselection cannot remove existing client configuration."
  }
}

run "rejects_unsupported_client" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["unsupported-agent"]
  }

  expect_failures = [var.clients]
}

run "rejects_unsupported_default" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["codex"]
    default  = ["custom-server"]
  }

  expect_failures = [var.default]
}

run "rejects_unpinned_tool_version" {
  command = plan

  variables {
    agent_id        = "test-agent"
    clients         = ["codex"]
    mcp_add_version = "latest"
  }

  expect_failures = [var.mcp_add_version]
}
