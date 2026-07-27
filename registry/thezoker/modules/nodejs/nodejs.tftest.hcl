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
    condition     = length(var.node_versions) == 3
    error_message = "node_versions should have 3 entries"
  }

  assert {
    condition     = strcontains(local.install_script, "v0.39.7")
    error_message = "install script should embed the configured nvm_version"
  }
}

run "test_script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent-outputs"
  }

  assert {
    condition     = length(output.scripts) == 1 && output.scripts[0] == "thezoker-nodejs-install_script"
    error_message = "scripts output should list only the install script when pre/post are not configured"
  }
}

run "test_script_outputs_with_pre_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent-outputs-all"
    pre_install_script  = "echo 'Pre-install script'"
    post_install_script = "echo 'Post-install script'"
  }

  assert {
    condition     = output.scripts == ["thezoker-nodejs-pre_install_script", "thezoker-nodejs-install_script", "thezoker-nodejs-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}

run "test_script_outputs_with_pre_install_only" {
  command = plan

  variables {
    agent_id           = "test-agent-pre"
    pre_install_script = "echo 'pre-install'"
  }

  assert {
    condition     = output.scripts == ["thezoker-nodejs-pre_install_script", "thezoker-nodejs-install_script"]
    error_message = "scripts output should list pre_install then install when only pre is configured"
  }
}

run "test_script_outputs_with_post_install_only" {
  command = plan

  variables {
    agent_id            = "test-agent-post"
    post_install_script = "echo 'post-install'"
  }

  assert {
    condition     = output.scripts == ["thezoker-nodejs-install_script", "thezoker-nodejs-post_install_script"]
    error_message = "scripts output should list install then post_install when only post is configured"
  }
}
