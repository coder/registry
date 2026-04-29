run "test_default_agentapi_port" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.agentapi_port == 3284
    error_message = "agentapi_port should default to 3284"
  }
}

run "test_custom_agentapi_port" {
  command = plan

  variables {
    agent_id      = "test-agent"
    agentapi_port = 3285
  }

  assert {
    condition     = var.agentapi_port == 3285
    error_message = "agentapi_port should be configurable"
  }
}
