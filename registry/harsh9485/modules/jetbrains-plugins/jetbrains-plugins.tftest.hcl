run "no_script_when_plugins_empty" {
  command = plan

  variables {
    agent_id          = "foo"
    jetbrains_plugins = {}
  }

  assert {
    condition     = length(resource.coder_script.install_jetbrains_plugins) == 0
    error_message = "Expected no plugin install script when plugins map is empty"
  }
}

run "script_created_when_plugins_provided" {
  command = plan

  variables {
    agent_id = "foo"
    jetbrains_plugins = {
      "PY" = ["com.koxudaxi.pydantic", "com.intellij.kubernetes"]
    }
  }

  assert {
    condition     = length(resource.coder_script.install_jetbrains_plugins) == 1
    error_message = "Expected script to be created when plugins are provided"
  }
}

run "rejects_invalid_product_code" {
  command = plan

  variables {
    agent_id = "foo"
    jetbrains_plugins = {
      "INVALID" = ["com.example.plugin"]
    }
  }

  expect_failures = [
    var.jetbrains_plugins,
  ]
}
