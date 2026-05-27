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
