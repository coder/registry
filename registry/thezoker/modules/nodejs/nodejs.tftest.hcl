run "test_nodejs_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.nvm_version == "master"
    error_message = "nvm_version should default to master"
  }

  assert {
    condition     = var.default_node_version == "node"
    error_message = "default_node_version should default to node"
  }

  assert {
    condition     = var.pre_install_script == null
    error_message = "pre_install_script should default to null"
  }

  assert {
    condition     = var.post_install_script == null
    error_message = "post_install_script should default to null"
  }
}

run "test_with_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-scripts"
    pre_install_script  = "echo 'Pre-install script'"
    post_install_script = "echo 'Post-install script'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install script'"
    error_message = "Pre-install script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install script'"
    error_message = "Post-install script should be set correctly"
  }
}

run "test_custom_options" {
  command = plan

  variables {
    agent_id             = "test-agent-custom"
    nvm_version          = "v0.39.7"
    nvm_install_prefix   = ".custom-nvm"
    node_versions        = ["18", "20", "node"]
    default_node_version = "20"
  }

  assert {
    condition     = var.nvm_version == "v0.39.7"
    error_message = "nvm_version should be set to v0.39.7"
  }

  assert {
    condition     = var.nvm_install_prefix == ".custom-nvm"
    error_message = "nvm_install_prefix should be set correctly"
  }

  assert {
    condition     = length(var.node_versions) == 3
    error_message = "node_versions should have 3 entries"
  }

  assert {
    condition     = var.default_node_version == "20"
    error_message = "default_node_version should be set to 20"
  }
}

run "test_with_pre_install_only" {
  command = plan

  variables {
    agent_id           = "test-agent-pre"
    pre_install_script = "echo 'pre-install'"
  }

  assert {
    condition     = var.pre_install_script != null
    error_message = "Pre-install script should be set"
  }

  assert {
    condition     = var.post_install_script == null
    error_message = "Post-install script should default to null"
  }
}

run "test_with_post_install_only" {
  command = plan

  variables {
    agent_id            = "test-agent-post"
    post_install_script = "echo 'post-install'"
  }

  assert {
    condition     = var.pre_install_script == null
    error_message = "Pre-install script should default to null"
  }

  assert {
    condition     = var.post_install_script != null
    error_message = "Post-install script should be set"
  }
}
