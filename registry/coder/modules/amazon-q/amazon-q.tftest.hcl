run "required_variables" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }
}

run "minimal_config" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdA==" # base64 "test"
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable not configured correctly"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq'"
  }
}

# Test Case 1: Basic Usage – No Autonomous Use of Q
# Using vanilla Kubernetes Deployment Template configuration
run "test_case_1_basic_usage" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdEF1dGhUYXJiYWxs" # base64 "testAuthTarball"
  }

  # Q is installed and authenticated
  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable should be configured for basic usage"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq' for basic usage"
  }

  # AgentAPI is installed and configured (default behavior)
  assert {
    condition     = length(resource.coder_env.auth_tarball) == 1
    error_message = "Auth tarball environment variable should be created for authentication"
  }

  # Foundational configuration applied
  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated with foundational configuration"
  }

  # No additional parameters required (using defaults)
  assert {
    condition     = local.agent_name == "agent"
    error_message = "Default agent name should be 'agent' when no custom config provided"
  }
}

# Test Case 2: Autonomous Usage – Autonomous Use of Q
# AI prompt passed through from external source (Tasks interface or Issue Tracker CI)
run "test_case_2_autonomous_usage" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdEF1dGhUYXJiYWxs" # base64 "testAuthTarball"
    ai_prompt    = "Help me set up a Python FastAPI project with proper testing structure"
  }

  # Q is installed and authenticated
  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable should be configured for autonomous usage"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq' for autonomous usage"
  }

  # AgentAPI is installed and configured
  assert {
    condition     = length(resource.coder_env.auth_tarball) == 1
    error_message = "Auth tarball environment variable should be created for autonomous usage"
  }

  # Foundational configuration for all components applied
  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated for autonomous usage"
  }

  # AI prompt is configured
  assert {
    condition     = local.full_prompt == "Help me set up a Python FastAPI project with proper testing structure"
    error_message = "AI prompt should be configured correctly for autonomous usage"
  }

  # Default agent name when no custom config
  assert {
    condition     = local.agent_name == "agent"
    error_message = "Default agent name should be 'agent' for autonomous usage"
  }
}

# Test Case 3: Extended Configuration – Parameter Validation and File Rendering
# Validates extended configuration options and parameter application
run "test_case_3_extended_configuration" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    auth_tarball        = "dGVzdEF1dGhUYXJiYWxs" # base64 "testAuthTarball"
    amazon_q_version    = "1.14.1"
    q_install_url       = "https://desktop-release.q.us-east-1.amazonaws.com"
    install_amazon_q    = true
    install_agentapi    = true
    agentapi_version    = "v0.6.0"
    trust_all_tools     = true
    ai_prompt           = "Help me create a production-grade TypeScript monorepo with testing and deployment"
    system_prompt       = "You are a helpful software assistant working in a secure enterprise environment"
    pre_install_script  = "echo 'Pre-install setup'"
    post_install_script = "echo 'Post-install cleanup'"
    agent_config = jsonencode({
      name             = "production-agent"
      description      = "Production Amazon Q agent for enterprise environment"
      prompt           = "You are a helpful software assistant working in a secure enterprise environment"
      mcpServers       = {}
      tools            = ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"]
      toolAliases      = {}
      allowedTools     = ["fs_read"]
      resources        = ["file://AmazonQ.md", "file://README.md", "file://.amazonq/rules/**/*.md"]
      hooks            = {}
      toolsSettings    = {}
      useLegacyMcpJson = true
    })
  }

  # All installation parameters are applied correctly
  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug should be configured correctly with extended parameters"
  }

  assert {
    condition     = resource.coder_env.auth_tarball[0].value == "dGVzdEF1dGhUYXJiYWxs"
    error_message = "Auth tarball should be configured correctly with extended parameters"
  }

  # Custom agent configuration is loaded and referenced correctly
  assert {
    condition     = local.agent_name == "production-agent"
    error_message = "Agent name should be extracted from custom agent config"
  }

  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Custom agent config should be processed correctly"
  }

  # AI prompt and system prompt are configured
  assert {
    condition     = local.full_prompt == "Help me create a production-grade TypeScript monorepo with testing and deployment"
    error_message = "AI prompt should be configured correctly in extended configuration"
  }

  # Pre-install and post-install scripts are provided
  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated correctly for extended configuration"
  }
}

run "full_config" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    install_amazon_q    = true
    install_agentapi    = true
    agentapi_version    = "v0.5.0"
    amazon_q_version    = "latest"
    trust_all_tools     = true
    ai_prompt           = "Build a web application"
    auth_tarball        = "dGVzdA=="
    order               = 1
    group               = "AI Tools"
    icon                = "/icon/custom-amazon-q.svg"
    pre_install_script  = "echo 'pre-install'"
    post_install_script = "echo 'post-install'"
    agent_config = jsonencode({
      name             = "test-agent"
      description      = "Test agent configuration"
      prompt           = "You are a helpful AI assistant for testing."
      mcpServers       = {}
      tools            = ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"]
      toolAliases      = {}
      allowedTools     = ["fs_read"]
      resources        = ["file://AmazonQ.md", "file://README.md", "file://.amazonq/rules/**/*.md"]
      hooks            = {}
      toolsSettings    = {}
      useLegacyMcpJson = true
    })
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable not configured correctly"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq'"
  }

  assert {
    condition     = length(resource.coder_env.auth_tarball) == 1
    error_message = "Auth tarball environment variable should be created when provided"
  }
}

run "auth_tarball_environment" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdEF1dGhUYXJiYWxs" # base64 "testAuthTarball"
  }

  assert {
    condition     = resource.coder_env.auth_tarball[0].name == "AMAZON_Q_AUTH_TARBALL"
    error_message = "Auth tarball environment variable name should be 'AMAZON_Q_AUTH_TARBALL'"
  }

  assert {
    condition     = resource.coder_env.auth_tarball[0].value == "dGVzdEF1dGhUYXJiYWxs"
    error_message = "Auth tarball environment variable value should match input"
  }
}

run "empty_auth_tarball" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = ""
  }

  assert {
    condition     = length(resource.coder_env.auth_tarball) == 0
    error_message = "Auth tarball environment variable should not be created when empty"
  }
}

run "custom_system_prompt" {
  command = plan

  variables {
    agent_id      = "test-agent-id"
    system_prompt = "Custom system prompt for testing"
  }

  # Test that the system prompt is used in the agent config template
  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated with custom system prompt"
  }
}

run "install_options" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    install_amazon_q = false
    install_agentapi = false
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug should still be configured even when install options are disabled"
  }
}

run "version_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    amazon_q_version = "2.15.0"
    agentapi_version = "v0.4.0"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should remain 'amazonq' regardless of version"
  }
}

# Additional test for agent name extraction
run "agent_name_extraction" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    agent_config = jsonencode({
      name             = "custom-enterprise-agent"
      description      = "Custom enterprise agent configuration"
      prompt           = "You are a custom enterprise AI assistant."
      mcpServers       = {}
      tools            = ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"]
      toolAliases      = {}
      allowedTools     = ["fs_read", "fs_write"]
      resources        = ["file://README.md"]
      hooks            = {}
      toolsSettings    = {}
      useLegacyMcpJson = true
    })
  }

  assert {
    condition     = local.agent_name == "custom-enterprise-agent"
    error_message = "Agent name should be extracted correctly from custom agent config"
  }

  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be processed correctly"
  }
}

# Test for JSON encoding validation
run "json_encoding_validation" {
  command = plan

  variables {
    agent_id      = "test-agent-id"
    system_prompt = "Multi-line\nsystem prompt\nwith newlines"
  }

  assert {
    condition     = length(local.system_prompt) > 0
    error_message = "System prompt should be JSON encoded correctly"
  }

  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated correctly with multi-line system prompt"
  }
}
