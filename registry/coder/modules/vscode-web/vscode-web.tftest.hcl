run "required_vars" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
  }
}

run "accept_license_required" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = false
  }

  expect_failures = [
    var.accept_license
  ]
}

run "offline_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    use_cached     = true
    offline        = true
  }

  expect_failures = [
    resource.coder_script.vscode-web
  ]
}

run "offline_disallows_extensions" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    offline        = true
    extensions     = ["ms-python.python", "golang.go"]
  }

  expect_failures = [
    resource.coder_script.vscode-web
  ]
}

run "workspace_and_folder_conflict" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    folder         = "/home/coder/project"
    workspace      = "/home/coder/project.code-workspace"
  }

  expect_failures = [
    resource.coder_script.vscode-web
  ]
}

run "url_with_folder_query" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    folder         = "/home/coder/project"
    port           = 13338
  }

  assert {
    condition     = resource.coder_app.vscode-web.url == "http://localhost:13338?folder=%2Fhome%2Fcoder%2Fproject"
    error_message = "coder_app URL must include encoded folder query param"
  }
}

run "url_with_workspace_query" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    workspace      = "/home/coder/project.code-workspace"
    port           = 13338
  }

  assert {
    condition     = resource.coder_app.vscode-web.url == "http://localhost:13338?workspace=%2Fhome%2Fcoder%2Fproject.code-workspace"
    error_message = "coder_app URL must include encoded workspace query param"
  }
}

run "release_channel_stable" {
  command = plan

  variables {
    agent_id        = "foo"
    accept_license  = true
    release_channel = "stable"
  }
}

run "release_channel_insiders" {
  command = plan

  variables {
    agent_id        = "foo"
    accept_license  = true
    release_channel = "insiders"
  }
}

run "release_channel_invalid" {
  command = plan

  variables {
    agent_id        = "foo"
    accept_license  = true
    release_channel = "invalid"
  }

  expect_failures = [
    var.release_channel
  ]
}

run "commit_id_empty_by_default" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
  }
}

run "commit_id_with_value" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    commit_id      = "e54c774e0add60467559eb0d1e229c6452cf8447"
  }
}
