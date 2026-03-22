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
    folder         = "/home/coder"
    gemini_api_key = "test-api-key-123"
  }

  assert {
    condition     = coder_env.gemini_api_key[0].value == "test-api-key-123"
    error_message = "Gemini API key value should match the input"
  }
}

run "test_enable_state_persistence_default" {
  command = plan

  variables {
    agent_id = "test-agent"
    folder   = "/home/coder"
  }

  assert {
    condition     = var.enable_state_persistence == true
    error_message = "enable_state_persistence should default to true"
  }
}

run "test_disable_state_persistence" {
  command = plan

  variables {
    agent_id                 = "test-agent"
    folder                   = "/home/coder"
    enable_state_persistence = false
  }

  assert {
    condition     = var.enable_state_persistence == false
    error_message = "enable_state_persistence should be false when explicitly disabled"
  }
}