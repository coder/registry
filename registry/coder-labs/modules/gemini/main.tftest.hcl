run "test_gemini_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    folder   = "/home/coder/projects"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.folder == "/home/coder/projects"
    error_message = "Folder variable should be set correctly"
  }

  assert {
    condition     = var.install_gemini == true
    error_message = "install_gemini should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "install_agentapi should default to true"
  }

  assert {
    condition     = var.use_vertexai == false
    error_message = "use_vertexai should default to false"
  }

  assert {
    condition     = var.enable_yolo_mode == false
    error_message = "enable_yolo_mode should default to false"
  }
}

run "test_gemini_with_api_key" {
  command = plan

  variables {
    agent_id       = "test-agent-456"
    folder         = "/home/coder/workspace"
    gemini_api_key = "test-api-key-123"
  }

  assert {
    condition     = coder_env.gemini_api_key[0].value == "test-api-key-123"
    error_message = "Gemini API key value should match the input"
  }
}
