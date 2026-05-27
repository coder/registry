run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "default_output" {
  command = plan

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = output.trae_cn_url == "trae-cn://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "Default trae_cn_url must match expected value"
  }
}

run "adds_folder" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/foo/bar"
  }

  assert {
    condition     = output.trae_cn_url == "trae-cn://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "URL must include folder parameter"
  }
}

run "folder_and_open_recent" {
  command = plan

  variables {
    agent_id    = "foo"
    folder      = "/foo/bar"
    open_recent = true
  }

  assert {
    condition     = output.trae_cn_url == "trae-cn://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "URL must include folder and openRecent parameters"
  }
}

run "adds_open_recent" {
  command = plan

  variables {
    agent_id    = "foo"
    open_recent = true
  }

  assert {
    condition     = output.trae_cn_url == "trae-cn://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "URL must include openRecent parameter"
  }
}

run "writes_mcp_json" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/foo/bar"
    mcp = jsonencode({
      mcpServers = {
        demo = { url = "http://localhost:1234" }
      }
    })
  }

  assert {
    condition = strcontains(coder_script.trae_cn_mcp[0].script, base64encode(jsonencode({
      mcpServers = {
        demo = { url = "http://localhost:1234" }
      }
    })))
    error_message = "coder_script must contain base64-encoded MCP JSON"
  }

  assert {
    condition     = strcontains(coder_script.trae_cn_mcp[0].script, base64encode("/foo/bar/.trae/mcp.json"))
    error_message = "coder_script must contain the default folder MCP path"
  }
}

run "writes_custom_mcp_path" {
  command = plan

  variables {
    agent_id        = "foo"
    mcp_config_path = "$HOME/.config/trae/mcp.json"
    mcp = jsonencode({
      mcpServers = {
        demo = { url = "http://localhost:1234" }
      }
    })
  }

  assert {
    condition     = strcontains(coder_script.trae_cn_mcp[0].script, base64encode("$HOME/.config/trae/mcp.json"))
    error_message = "coder_script must contain the custom MCP path"
  }
}
