mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      name       = "dev-workspace"
      access_url = "https://coder.example.test"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = { name = "test-owner" }
  }
}

variables {
  agent_id = "test-agent"
  folder   = "/home/coder/project"
}

run "live_share_launch" {
  command = apply

  assert {
    condition     = output.vscode_url == "vscode://coder.coder-remote/open?liveShare=true&owner=test-owner&workspace=dev-workspace&folder=%2Fhome%2Fcoder%2Fproject&url=https%3A%2F%2Fcoder.example.test&token=$SESSION_TOKEN"
    error_message = "The button must request Live Share for the selected folder using the Coder session token placeholder."
  }
  assert {
    condition     = coder_app.liveshare.display_name == "Open Liveshare" && coder_app.liveshare.external && coder_app.liveshare.agent_id == "test-agent"
    error_message = "The external button must be attached to the selected agent."
  }
}

run "encode_folder_and_select_agent" {
  command = apply
  variables {
    folder     = "/home/coder/a & b#?=+é"
    agent_name = "main"
    order      = 3
    group      = "Collaboration"
  }
  assert {
    condition     = strcontains(output.vscode_url, "&folder=%2Fhome%2Fcoder%2Fa+%26+b%23%3F%3D%2B%C3%A9&agent=main&url=")
    error_message = "Folder characters must not inject or truncate query parameters."
  }
  assert {
    condition     = coder_app.liveshare.order == 3 && coder_app.liveshare.group == "Collaboration"
    error_message = "The button must preserve custom UI placement."
  }
}

run "reject_relative_folder" {
  command = plan
  variables { folder = "project" }
  expect_failures = [var.folder]
}

run "reject_folder_line_breaks" {
  command = plan
  variables { folder = "/project\nother" }
  expect_failures = [var.folder]
}

run "reject_empty_agent" {
  command = plan
  variables { agent_name = " " }
  expect_failures = [var.agent_name]
}
