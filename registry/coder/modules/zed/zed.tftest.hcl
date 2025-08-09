run "default_output" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = output.zed_url == "zed://ssh/default.coder"
    error_message = "zed_url did not match expected default URL"
  }
}

run "adds_folder" {
  command = apply

  variables {
    agent_id = "foo"
    folder   = "/foo/bar"
  }

  assert {
    condition     = output.zed_url == "zed://ssh/default.coder/foo/bar"
    error_message = "zed_url did not include provided folder path"
  }
}

run "adds_agent_name" {
  command = apply

  variables {
    agent_id   = "foo"
    agent_name = "myagent"
  }

  assert {
    condition     = output.zed_url == "zed://ssh/myagent.default.default.coder"
    error_message = "zed_url did not include agent_name in hostname"
  }
}
