run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }
}

run "app_url_uses_port" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    port     = 19999
  }

  assert {
    condition     = resource.coder_app.module_name.url == "http://localhost:19999"
    error_message = "Expected module-name app URL to include configured port"
  }
}
