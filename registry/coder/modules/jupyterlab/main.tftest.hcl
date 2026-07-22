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
    condition     = strcontains(coder_script.jupyterlab.script, "--ServerApp.ip='127.0.0.1'")
    error_message = "the default script must bind JupyterLab to 127.0.0.1"
  }

  assert {
    condition     = !strcontains(coder_script.jupyterlab.script, "0.0.0.0") && !strcontains(coder_script.jupyterlab.script, "--ServerApp.ip='*'")
    error_message = "the default script must not bind JupyterLab to all interfaces"
  }

  assert {
    condition     = coder_app.jupyterlab.url == "http://localhost:19999"
    error_message = "the default Coder application URL must remain unchanged"
  }

  assert {
    condition     = one(coder_app.jupyterlab.healthcheck).url == "http://localhost:19999/api"
    error_message = "the JupyterLab healthcheck URL must remain unchanged"
  }
}

run "path_mode_and_external_host" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    host      = "0.0.0.0"
    subdomain = false
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      name = "example-workspace"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "example-owner"
    }
  }

  assert {
    condition     = strcontains(coder_script.jupyterlab.script, "--ServerApp.ip='0.0.0.0'")
    error_message = "the script must render an explicitly configured host"
  }

  assert {
    condition     = strcontains(coder_script.jupyterlab.script, "--ServerApp.base_url=/@example-owner/example-workspace/apps/jupyterlab")
    error_message = "the JupyterLab base URL must remain unchanged in path mode"
  }

  assert {
    condition     = coder_app.jupyterlab.url == "http://localhost:19999/@example-owner/example-workspace/apps/jupyterlab"
    error_message = "the JupyterLab application URL must remain unchanged in path mode"
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
