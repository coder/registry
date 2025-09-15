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
