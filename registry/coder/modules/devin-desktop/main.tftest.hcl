mock_provider "coder" {}

variables {
  agent_id = "test-agent"
}

run "defaults_preserve_devin_uri" {
  command = plan

  assert {
    condition     = startswith(output.devin_desktop_url, "devin://coder.coder-remote/open")
    error_message = "The default app URL must keep the devin protocol."
  }
}

run "extensions_accept_devin_compatible_ids" {
  command = plan

  variables {
    extensions = [
      "ms-python.python",
      "esbenp.prettier-vscode@12.4.0",
    ]
  }

  assert {
    condition     = length(var.extensions) == 2
    error_message = "The Devin Desktop wrapper must accept configured extension IDs."
  }
}
