run "test_no_plugins" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    plugins  = []
  }

  assert {
    condition     = coder_script.jetbrains_plugins.display_name == "JetBrains Plugin Installer"
    error_message = "Display name should be 'JetBrains Plugin Installer'"
  }

  assert {
    condition     = coder_script.jetbrains_plugins.run_on_start == true
    error_message = "Script should run on start"
  }
}

run "test_with_plugins" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    plugins  = ["org.jetbrains.plugins.github", "Docker"]
  }

  assert {
    condition     = length(var.plugins) == 2
    error_message = "Should have 2 plugins configured"
  }
}

run "test_multiple_ides" {
  command = plan

  variables {
    agent_id          = "test-agent-id"
    plugins           = ["Docker"]
    ide_product_codes = ["IU", "GO", "PY"]
  }

  assert {
    condition     = length(var.ide_product_codes) == 3
    error_message = "Should have 3 IDEs configured"
  }
}

run "test_custom_plugins_dir" {
  command = plan

  variables {
    agent_id    = "test-agent-id"
    plugins     = ["Docker"]
    plugins_dir = "/custom/plugins/path"
  }

  assert {
    condition     = var.plugins_dir == "/custom/plugins/path"
    error_message = "Custom plugins dir should be set"
  }
}
