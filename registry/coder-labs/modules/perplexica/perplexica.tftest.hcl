run "plan_basic" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = resource.coder_app.perplexica.url == "http://localhost:3000"
    error_message = "Default port should be 3000"
  }
}

run "plan_custom_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 8080
  }

  assert {
    condition     = resource.coder_app.perplexica.url == "http://localhost:8080"
    error_message = "Should use custom port"
  }
}
