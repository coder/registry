run "parameter_name" {
  command = plan

  assert {
    condition     = data.coder_parameter.region[0].name == "aws_region"
    error_message = "Parameter name should be aws_region"
  }
}

run "custom_order" {
  command = plan

  variables {
    coder_parameter_order = 99
  }

  assert {
    condition     = data.coder_parameter.region[0].order == 99
    error_message = "coder_parameter_order should propagate to the parameter order"
  }
}

run "all_regions_are_options" {
  command = plan

  assert {
    condition     = length(data.coder_parameter.region[0].option) == length(local.regions)
    error_message = "Every catalog region should be rendered as a selectable option"
  }
}

run "default_output_empty" {
  command = apply

  assert {
    condition     = output.value == "" && output.default_availability_zone == ""
    error_message = "With no default and no selection, value and default_availability_zone should be empty"
  }
}

run "custom_default" {
  command = apply

  variables {
    default = "us-west-2"
  }

  assert {
    condition     = output.value == "us-west-2" && output.default_availability_zone == "us-west-2a"
    error_message = "value and default_availability_zone should follow the configured default"
  }
}

run "regions_output_exposes_catalog" {
  command = plan

  assert {
    condition     = length(output.regions) == length(local.regions)
    error_message = "regions output should expose every catalog entry keyed by ID"
  }

  assert {
    condition = (
      output.regions["ap-northeast-1"].name == "Asia Pacific (Tokyo)" &&
      output.regions["ap-northeast-1"].country == "jp" &&
      output.regions["ap-northeast-1"].icon == "/emojis/1f1ef-1f1f5.png" &&
      output.regions["ap-northeast-1"].default_availability_zone == "ap-northeast-1a"
    )
    error_message = "regions entries should expose name, country, icon, and default_availability_zone"
  }
}

run "exclude_removes_option" {
  command = apply

  variables {
    exclude = ["ap-northeast-2", "ap-northeast-3"]
  }

  assert {
    condition = (
      !contains([for o in data.coder_parameter.region[0].option : o.value], "ap-northeast-2") &&
      !contains([for o in data.coder_parameter.region[0].option : o.value], "ap-northeast-3")
    )
    error_message = "Excluded regions should not appear as options"
  }
}

run "custom_names_and_icons_override" {
  command = apply

  variables {
    custom_names = {
      "ap-south-1" = "Awesome Mumbai!"
    }
    custom_icons = {
      "ap-south-1" = "/emojis/1f33a.png"
    }
  }

  assert {
    condition     = length([for o in data.coder_parameter.region[0].option : o if o.value == "ap-south-1" && o.name == "Awesome Mumbai!" && o.icon == "/emojis/1f33a.png"]) == 1
    error_message = "custom_names and custom_icons should override the defaults for a region"
  }
}

run "outputs_without_parameter" {
  command = apply

  variables {
    create_parameter = false
    default          = "eu-west-1"
  }

  assert {
    condition     = length(data.coder_parameter.region) == 0
    error_message = "create_parameter = false should not create the coder_parameter"
  }

  assert {
    condition     = output.value == "eu-west-1" && output.default_availability_zone == "eu-west-1a"
    error_message = "With create_parameter = false, outputs should fall back to var.default"
  }
}
