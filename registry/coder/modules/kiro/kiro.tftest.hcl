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
    condition     = output.kiro_url == "kiro://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "Default kiro_url must match expected value"
  }

  assert {
    condition     = coder_app.kiro.order == null
    error_message = "coder_app order must be null by default"
  }
}

run "adds_folder" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/foo/bar"
  }

  assert {
    condition     = output.kiro_url == "kiro://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
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
    condition     = output.kiro_url == "kiro://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN"
    error_message = "URL must include folder and openRecent parameters"
  }
}

run "custom_slug_display_name" {
  command = plan

  variables {
    agent_id     = "foo"
    slug         = "kiro-ai"
    display_name = "Kiro AI IDE"
  }

  assert {
    condition     = coder_app.kiro.slug == "kiro-ai"
    error_message = "coder_app slug must be set to kiro-ai"
  }

  assert {
    condition     = coder_app.kiro.display_name == "Kiro AI IDE"
    error_message = "coder_app display_name must be set to Kiro AI IDE"
  }
}

run "sets_order" {
  command = plan

  variables {
    agent_id = "foo"
    order    = 5
  }

  assert {
    condition     = coder_app.kiro.order == 5
    error_message = "coder_app order must be set to 5"
  }
}

run "sets_group" {
  command = plan

  variables {
    agent_id = "foo"
    group    = "AI IDEs"
  }

  assert {
    condition     = coder_app.kiro.group == "AI IDEs"
    error_message = "coder_app group must be set to AI IDEs"
  }
}

run "writes_mcp_json" {
  command = plan

  variables {
    agent_id = "foo"
    mcp = jsonencode({
      servers = {
        demo = { url = "http://localhost:1234" }
      }
    })
  }

  assert {
    condition = strcontains(coder_script.kiro_mcp[0].script, base64encode(jsonencode({
      servers = {
        demo = { url = "http://localhost:1234" }
      }
    })))
    error_message = "coder_script must contain base64-encoded MCP JSON"
  }
}