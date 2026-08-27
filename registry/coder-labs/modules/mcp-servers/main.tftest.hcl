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

run "explicit_none_preserves_install_pipeline" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["claude code", "codex", "cursor"]
    default  = ["github", "playwright"]
    github_auth = {
      mode = "none"
    }
  }

  assert {
    condition     = module.coder_utils.scripts == ["coder-labs-mcp-servers-install_script"]
    error_message = "Explicit mode none must preserve the original single install script pipeline."
  }
}

run "adds_token_env_auth_after_install" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["claude code", "codex", "cursor"]
    default  = ["github"]
    github_auth = {
      mode          = "token-env"
      token_env_var = "WORKSPACE_GITHUB_TOKEN"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "workspace-owner"
    }
  }

  assert {
    condition = module.coder_utils.scripts == [
      "coder-labs-mcp-servers-install_script",
      "coder-labs-mcp-servers-post_install_script",
    ]
    error_message = "Authenticated GitHub configuration must run after the baseline install script."
  }
}

run "rejects_external_auth_for_unsupported_clients" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["claude code", "cursor"]
    default  = ["github"]
    github_auth = {
      mode = "external-auth"
    }
  }

  expect_failures = [data.coder_parameter.mcp_servers]
}

run "rejects_unpinned_local_oauth_image" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["codex"]
    default  = ["github"]
    github_auth = {
      mode               = "native-oauth"
      local_server_image = "ghcr.io/github/github-mcp-server:latest"
    }
  }

  expect_failures = [var.github_auth]
}

run "prebuild_renders_auth_without_user_credentials" {
  command = plan

  variables {
    agent_id = "test-agent"
    clients  = ["claude code"]
    default  = ["github"]
    github_auth = {
      mode             = "external-auth"
      external_auth_id = "primary-github"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "prebuilds"
    }
  }

  assert {
    condition     = length(module.coder_utils.scripts) == 2
    error_message = "Prebuilds must retain the post-claim authentication script without resolving a user token during plan."
  }
}
