mock_provider "coder" {}

variables {
  agent_id = "test-agent"
}

run "defaults_preserve_vscode_uri" {
  command = plan

  assert {
    condition     = startswith(output.vscode_url, "vscode://coder.coder-remote/open")
    error_message = "The default app URL must keep the vscode protocol."
  }
}

run "extensions_accept_remote_ids" {
  command = plan

  variables {
    extensions = [
      "ms-python.python",
      "esbenp.prettier-vscode@12.4.0",
    ]
  }

  assert {
    condition     = length(var.extensions) == 2
    error_message = "The VS Code Desktop wrapper must accept configured extension IDs."
  }
}

run "extensions_reject_empty_ids" {
  command = plan

  variables {
    extensions = [""]
  }

  expect_failures = [
    var.extensions,
  ]
}
