variables {
  # Default IDE config, mirrored from main.tf for test assertions.
  # If main.tf defaults change, update this map to match.
  expected_ide_config = {
    "CL" = { name = "CLion", icon = "/icon/clion.svg", build = "251.26927.39" },
    "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "251.26927.50" },
    "IU" = { name = "IntelliJ IDEA", icon = "/icon/intellij.svg", build = "251.26927.53" },
    "PS" = { name = "PhpStorm", icon = "/icon/phpstorm.svg", build = "251.26927.60" },
    "PY" = { name = "PyCharm", icon = "/icon/pycharm.svg", build = "251.26927.74" },
    "RD" = { name = "Rider", icon = "/icon/rider.svg", build = "251.26927.67" },
    "RM" = { name = "RubyMine", icon = "/icon/rubymine.svg", build = "251.26927.47" },
    "RR" = { name = "RustRover", icon = "/icon/rustrover.svg", build = "251.26927.79" },
    "WS" = { name = "WebStorm", icon = "/icon/webstorm.svg", build = "251.26927.40" }
  }
}

run "validate_test_config_matches_defaults" {
  command = plan

  variables {
    # Provide minimal vars to allow plan to read module variables
    agent_id = "foo"
    folder   = "/home/coder"
  }

  assert {
    condition     = length(var.ide_config) == length(var.expected_ide_config)
    error_message = "Test configuration mismatch: 'var.ide_config' in main.tf has ${length(var.ide_config)} items, but 'var.expected_ide_config' in the test file has ${length(var.expected_ide_config)} items. Please update the test file's global variables block."
  }

  assert {
    # Check that all keys in the test local are present in the module's default
    condition = alltrue([
      for key in keys(var.expected_ide_config) :
      can(var.ide_config[key])
    ])
    error_message = "Test configuration mismatch: Keys in 'var.expected_ide_config' are out of sync with 'var.ide_config' defaults. Please update the test file's global variables block."
  }

  assert {
    # Check if all build numbers in the test local match the module's defaults
    # This relies on the previous two assertions passing (same length, same keys)
    condition = alltrue([
      for key, config in var.expected_ide_config :
      var.ide_config[key].build == config.build
    ])
    error_message = "Test configuration mismatch: One or more build numbers in 'var.expected_ide_config' do not match the defaults in 'var.ide_config'. Please update the test file's global variables block."
  }
}

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
    tooltip  = "You need to [Install Coder Desktop](https://coder.com/docs/user-guides/desktop#install-coder-desktop) to use this button."
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : app.tooltip == "You need to [Install Coder Desktop](https://coder.com/docs/user-guides/desktop#install-coder-desktop) to use this button."])
    error_message = "Expected coder_app tooltip to be set when provided"
  }
}

run "tooltip_null_when_not_provided" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
  }

  assert {
    condition     = anytrue([for app in values(resource.coder_app.jetbrains) : app.tooltip == null])
    error_message = "Expected coder_app tooltip to be null when not provided"
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

run "output_single_ide_uses_fallback_build" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    # Force HTTP data source to fail to test fallback logic
    releases_base_link = "https://coder.com"
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
    condition     = output.ide_metadata["GO"].name == var.expected_ide_config["GO"].name
    error_message = "Expected ide_metadata['GO'].name to be '${var.expected_ide_config["GO"].name}'"
  }

  assert {
    condition     = output.ide_metadata["GO"].build == var.expected_ide_config["GO"].build
    error_message = "Expected ide_metadata['GO'].build to use the fallback '${var.expected_ide_config["GO"].build}'"
  }

  assert {
    condition     = output.ide_metadata["GO"].icon == var.expected_ide_config["GO"].icon
    error_message = "Expected ide_metadata['GO'].icon to be '${var.expected_ide_config["GO"].icon}'"
  }
}

run "output_multiple_ides" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["IU", "PY"]
    # Force HTTP data source to fail to test fallback logic
    releases_base_link = "https://coder.com"
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
    condition     = output.ide_metadata["PY"].name == var.expected_ide_config["PY"].name
    error_message = "Expected ide_metadata['PY'].name to be '${var.expected_ide_config["PY"].name}'"
  }

  assert {
    condition     = output.ide_metadata["PY"].build == var.expected_ide_config["PY"].build
    error_message = "Expected ide_metadata['PY'].build to be the fallback '${var.expected_ide_config["PY"].build}'"
  }
}

run "no_script_when_plugins_empty" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    plugins  = []
  }

  assert {
    condition     = length(resource.coder_script.jetbrains_plugin_installer) == 0
    error_message = "Expected no coder_script when plugins list is empty"
  }
}

run "script_created_when_plugins_provided" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    plugins  = ["com.intellij.plugins.terminal", "org.rust.lang"]
  }

  assert {
    condition     = length(resource.coder_script.jetbrains_plugin_installer) == 1
    error_message = "Expected coder_script when plugins list is not empty"
  }
}

run "script_runs_on_start" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    default  = ["GO"]
    plugins  = ["com.intellij.plugins.terminal"]
  }

  assert {
    condition     = resource.coder_script.jetbrains_plugin_installer[0].run_on_start == true
    error_message = "Expected plugin installer script to run on start"
  }
}

run "no_script_when_no_ides_selected" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder"
    # default is empty, so no IDEs selected
    plugins = ["com.intellij.plugins.terminal"]
  }

  assert {
    condition     = length(resource.coder_script.jetbrains_plugin_installer) == 0
    error_message = "Expected no coder_script when no IDEs are selected even if plugins are specified"
  }
}
