run "requires_agent_and_folder" {
  command = plan

  # Setting both required vars should plan
  variables {
    agent_id = "foo"
    folder   = "/home/coder"
  }
}

run "creates_parameter_when_default_empty_latest" {
  command = plan

  variables {
    agent_id      = "foo"
    folder        = "/home/coder"
    major_version = "latest"
  }

  # When default is empty, a coder_parameter should be created
  assert {
    condition     = can(data.coder_parameter.jetbrains_ides[0].type)
    error_message = "Expected data.coder_parameter.jetbrains_ides to exist when default is empty"
  }
}

run "no_apps_when_default_empty" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
  }

  assert {
    condition     = length(resource.coder_app.jetbrains) == 0
    error_message = "Expected no coder_app resources when default is empty"
  }
}

run "single_app_when_default_GO" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
  }

  assert {
    condition     = length(resource.coder_app.jetbrains) == 1
    error_message = "Expected exactly one coder_app when default contains GO"
  }
}

run "url_contains_required_params" {
  command = apply

  variables {
    agent_id = "test-agent-123"
    folder   = "/custom/project/path"
    default  = ["GO"]
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("jetbrains://gateway/coder", app.url)) > 0])
    error_message = "URL must contain jetbrains scheme"
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("&folder=/custom/project/path", app.url)) > 0])
    error_message = "URL must include folder path"
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("ide_product_code=GO", app.url)) > 0])
    error_message = "URL must include product code"
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("ide_build_number=", app.url)) > 0])
    error_message = "URL must include build number"
  }
}

run "includes_agent_name_when_set" {
  command = apply

  variables {
    agent_id   = "test-agent-123"
    agent_name = "main-agent"
    folder     = "/custom/project/path"
    default    = ["GO"]
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("&agent_name=main-agent", app.url)) > 0])
    error_message = "URL must include agent_name when provided"
  }
}

run "parameter_order_when_default_empty" {
  command = plan

  variables {
    agent_id              = "foo"
    folder                = "/home/coder"
    coder_parameter_order = 5
  }

  assert {
    condition     = data.coder_parameter.jetbrains_ides[0].order == 5
    error_message = "Expected coder_parameter order to be set to 5"
  }
}

run "app_order_when_default_not_empty" {
  command = plan

  variables {
    agent_id        = "foo"
    folder          = "/home/coder"
    default         = ["GO"]
    coder_app_order = 10
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : app.order == 10])
    error_message = "Expected coder_app order to be set to 10"
  }
}

run "tooltip_when_provided" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    tooltip  = "You need to install [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/) to use this button."
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : app.tooltip == "You need to install [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/) to use this button."])
    error_message = "Expected coder_app tooltip to be set when provided"
  }
}

run "tooltip_default_when_not_provided" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : app.tooltip == "You need to install [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/) to use this button."])
    error_message = "Expected coder_app tooltip to be the default JetBrains Toolbox message when not provided"
  }
}

run "channel_eap" {
  command = plan

  variables {
    agent_id      = "foo"
    folder        = "/home/coder"
    default       = ["GO"]
    channel       = "eap"
    major_version = "latest"
  }

  assert {
    condition     = output.ide_metadata["GO"].json_data.type == "eap"
    error_message = "Expected the API to return a release of type 'eap', but got '${output.ide_metadata["GO"].json_data.type}'"
  }
}

run "specific_major_version" {
  command = plan

  variables {
    agent_id      = "foo"
    folder        = "/home/coder"
    default       = ["GO"]
    major_version = "2025.3"
  }

  assert {
    condition     = output.ide_metadata["GO"].json_data.majorVersion == "2025.3"
    error_message = "Expected the API to return a release for major version '2025.3', but got '${output.ide_metadata["GO"].json_data.majorVersion}'"
  }
}

run "output_empty_when_default_empty" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    # var.default is empty
  }

  assert {
    condition     = length(output.ide_metadata) == 0
    error_message = "Expected ide_metadata output to be empty when var.default is not set"
  }
}

run "uses_ide_config_when_set" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    options  = ["GO"]
    ide_config = {
      "GO" = { name = "GoLand Custom", icon = "/icon/goland.svg", build = "999.99999.999" }
    }
  }

  assert {
    condition     = length(output.ide_metadata) == 1
    error_message = "Expected ide_metadata output to have 1 item"
  }

  assert {
    condition     = can(output.ide_metadata["GO"])
    error_message = "Expected ide_metadata output to have key 'GO'"
  }

  assert {
    condition     = output.ide_metadata["GO"].name == "GoLand Custom"
    error_message = "Expected ide_metadata['GO'].name to be 'GoLand Custom'"
  }

  assert {
    condition     = output.ide_metadata["GO"].build == "999.99999.999"
    error_message = "Expected ide_metadata['GO'].build to use the pinned build '999.99999.999'"
  }

  assert {
    condition     = output.ide_metadata["GO"].icon == "/icon/goland.svg"
    error_message = "Expected ide_metadata['GO'].icon to be '/icon/goland.svg'"
  }

  assert {
    condition     = output.ide_metadata["GO"].json_data == null
    error_message = "Expected ide_metadata['GO'].json_data to be null when using ide_config"
  }
}

run "uses_ide_config_for_multiple_ides" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["IU", "PY"]
    options  = ["IU", "PY"]
    ide_config = {
      "IU" = { name = "IntelliJ IDEA", icon = "/icon/intellij.svg", build = "111.11111.111" }
      "PY" = { name = "PyCharm", icon = "/icon/pycharm.svg", build = "222.22222.222" }
    }
  }

  assert {
    condition     = length(output.ide_metadata) == 2
    error_message = "Expected ide_metadata output to have 2 items"
  }

  assert {
    condition     = can(output.ide_metadata["IU"]) && can(output.ide_metadata["PY"])
    error_message = "Expected ide_metadata output to have keys 'IU' and 'PY'"
  }

  assert {
    condition     = output.ide_metadata["PY"].name == "PyCharm"
    error_message = "Expected ide_metadata['PY'].name to be 'PyCharm'"
  }

  assert {
    condition     = output.ide_metadata["PY"].build == "222.22222.222"
    error_message = "Expected ide_metadata['PY'].build to be the pinned build '222.22222.222'"
  }

  assert {
    condition     = output.ide_metadata["IU"].build == "111.11111.111"
    error_message = "Expected ide_metadata['IU'].build to be the pinned build '111.11111.111'"
  }

  assert {
    condition     = output.ide_metadata["IU"].json_data == null
    error_message = "Expected ide_metadata['IU'].json_data to be null when using ide_config"
  }

  assert {
    condition     = output.ide_metadata["PY"].json_data == null
    error_message = "Expected ide_metadata['PY'].json_data to be null when using ide_config"
  }
}

run "ide_config_build_in_url" {
  command = apply

  variables {
    agent_id = "test-agent-123"
    folder   = "/home/coder/project"
    default  = ["GO"]
    options  = ["GO"]
    ide_config = {
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "999.99999.999" }
    }
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : length(regexall("ide_build_number=999.99999.999", app.url)) > 0])
    error_message = "URL must include the pinned build number from ide_config"
  }
}

run "validate_output_schema" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    options  = ["GO"]
    ide_config = {
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "253.28294.337" }
    }
  }

  assert {
    condition = alltrue([
      for key, meta in output.ide_metadata : (
        can(meta.icon) &&
        can(meta.name) &&
        can(meta.identifier) &&
        can(meta.key) &&
        can(meta.build) &&
        # json_data can be null, but the key must exist
        can(meta.json_data)
      )
    ])
    error_message = "The ide_metadata output schema has changed. Please update the 'main.tf' and this test."
  }
}

run "no_plugin_script_when_plugins_empty" {
  command = plan

  variables {
    agent_id          = "foo"
    folder            = "/home/coder"
    default           = ["PY"]
    jetbrains_plugins = {}
  }

  assert {
    condition     = length(resource.coder_script.install_jetbrains_plugins) == 0
    error_message = "Expected no plugin install script when plugins list is empty"
  }
}

run "plugin_script_created_when_plugins_provided" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["PY"]
    jetbrains_plugins = {
      "PY" = ["com.koxudaxi.pydantic", "com.intellij.kubernetes"]
    }
  }

  assert {
    condition     = length(resource.coder_script.install_jetbrains_plugins) == 1
    error_message = "Expected script to be created when plugins are provided"
  }
}

run "rejects_major_version_with_ide_config" {
  command = plan

  variables {
    agent_id      = "foo"
    folder        = "/home/coder"
    default       = ["GO"]
    options       = ["GO"]
    major_version = "2025.3"
    ide_config = {
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "253.31033.129" }
    }
  }

  expect_failures = [
    var.ide_config,
  ]
}

run "rejects_default_not_in_ide_config" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO", "IU"]
    options  = ["GO", "IU"]
    ide_config = {
      "GO" = { build = "253.31033.129" }
    }
  }

  expect_failures = [
    var.ide_config,
  ]
}

run "ide_config_with_build_only" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    options  = ["GO"]
    ide_config = {
      "GO" = { build = "999.99999.999" }
    }
  }

  assert {
    condition     = output.ide_metadata["GO"].name == "GoLand"
    error_message = "Expected name to fall back to ide_metadata when not set in ide_config"
  }

  assert {
    condition     = output.ide_metadata["GO"].icon == "/icon/goland.svg"
    error_message = "Expected icon to fall back to ide_metadata when not set in ide_config"
  }

  assert {
    condition     = output.ide_metadata["GO"].build == "999.99999.999"
    error_message = "Expected build to use ide_config value"
  }
}

run "rejects_releases_base_link_with_ide_config" {
  command = plan

  variables {
    agent_id           = "foo"
    folder             = "/home/coder"
    default            = ["GO"]
    options            = ["GO"]
    releases_base_link = "https://internal.mirror.example.com"
    ide_config = {
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "253.31033.129" }
    }
  }

  expect_failures = [
    var.ide_config,
  ]
}

run "rejects_channel_with_ide_config" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    options  = ["GO"]
    channel  = "eap"
    ide_config = {
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "253.31033.129" }
    }
  }

  expect_failures = [
    var.ide_config,
  ]
}
