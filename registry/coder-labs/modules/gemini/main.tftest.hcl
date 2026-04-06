run "test_gemini_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    folder   = "/home/coder"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.folder == "/home/coder"
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
    condition     = coder_env.gemini_api_key.value == "test-api-key-123"
    error_message = "Gemini API key value should match the input"
  }
}

run "test_gemini_with_custom_options" {
  command = plan

  variables {
    agent_id              = "test-agent-789"
    folder                = "/home/coder/custom"
    order                 = 5
    group                 = "development"
    icon                  = "/icon/custom.svg"
    gemini_version        = "1.0.0"
    gemini_model          = "gemini-2.5-pro"
    agentapi_version      = "v0.13.0"
    continue              = false
    pre_install_script    = "echo 'Pre-install script'"
    post_install_script   = "echo 'Post-install script'"
    task_prompt           = "Automate this task"
    additional_extensions = "{ \"my-extension\": {} }"
    gemini_system_prompt  = "Custom system prompt"
  }

  assert {
    condition     = var.order == 5
    error_message = "Order variable should be set to 5"
  }

  assert {
    condition     = var.group == "development"
    error_message = "Group variable should be set to 'development'"
  }

  assert {
    condition     = var.icon == "/icon/custom.svg"
    error_message = "Icon variable should be set to custom icon"
  }

  assert {
    condition     = var.gemini_version == "1.0.0"
    error_message = "Gemini version should be set to '1.0.0'"
  }

  assert {
    condition     = var.gemini_model == "gemini-2.5-pro"
    error_message = "Gemini model variable should be set to 'gemini-2.5-pro'"
  }

  assert {
    condition     = var.agentapi_version == "v0.13.0"
    error_message = "AgentAPI version should be set to 'v0.13.0'"
  }

  assert {
    condition     = var.continue == false
    error_message = "Continue should be set to false"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install script'"
    error_message = "Pre-install script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install script'"
    error_message = "Post-install script should be set correctly"
  }

  assert {
    condition     = var.task_prompt == "Automate this task"
    error_message = "Task prompt should be set correctly"
  }

  assert {
    condition     = var.additional_extensions == "{ \"my-extension\": {} }"
    error_message = "Additional extensions should be set correctly"
  }

  assert {
    condition     = var.gemini_system_prompt == "Custom system prompt"
    error_message = "Gemini system prompt should be set correctly"
  }
}

run "test_gemini_system_prompt" {
  command = plan

  variables {
    agent_id             = "test-agent-system-prompt"
    folder               = "/home/coder/test"
    gemini_system_prompt = "Custom addition"
  }

  assert {
    condition     = trimspace(var.gemini_system_prompt) != ""
    error_message = "System prompt should not be empty"
  }

  assert {
    condition     = length(regexall("Custom addition", var.gemini_system_prompt)) > 0
    error_message = "System prompt should have system_prompt variable value"
  }
}

run "test_no_api_key_no_env" {
  command = plan

  variables {
    agent_id = "test-agent-no-key"
    folder   = "/home/coder/test"
  }

  assert {
    condition     = coder_env.gemini_api_key.value == ""
    error_message = "GEMINI_API_KEY should not be created when no API key is provided"
  }

  assert {
    condition     = coder_env.google_api_key.value == ""
    error_message = "GOOGLE_API_KEY should not be created when no API key is provided"
  }
}

run "test_gemini_with_vertexai" {
  command = plan

  variables {
    agent_id       = "test-agent-vertexai"
    folder         = "/home/coder"
    use_vertexai   = true
    gemini_api_key = "test-key"
  }

  assert {
    condition     = coder_env.gemini_use_vertex_ai.value == "true"
    error_message = "GOOGLE_GENAI_USE_VERTEXAI should be true when use_vertexai is enabled"
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
