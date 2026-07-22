run "secure_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = var.host == "127.0.0.1"
    error_message = "host must default to 127.0.0.1"
  }

  assert {
    condition     = strcontains(coder_script.jupyter-notebook.script, "--NotebookApp.ip='127.0.0.1'")
    error_message = "the default script must bind Jupyter Notebook to 127.0.0.1"
  }

  assert {
    condition     = !strcontains(coder_script.jupyter-notebook.script, "0.0.0.0") && !strcontains(coder_script.jupyter-notebook.script, "--NotebookApp.ip='*'") && !strcontains(coder_script.jupyter-notebook.script, "--ServerApp.ip='*'")
    error_message = "the default script must not bind Jupyter Notebook to all interfaces"
  }

  assert {
    condition     = coder_app.jupyter-notebook.url == "http://localhost:19999"
    error_message = "the default Coder application URL must remain unchanged"
  }
}

run "explicit_external_host" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    host     = "0.0.0.0"
  }

  assert {
    condition     = strcontains(coder_script.jupyter-notebook.script, "--NotebookApp.ip='0.0.0.0'")
    error_message = "the script must render an explicitly configured host"
  }
}

run "unsafe_host_rejected" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    host     = "127.0.0.1; touch /tmp/injected"
  }

  expect_failures = [
    var.host,
  ]
}
