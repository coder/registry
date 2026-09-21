run "parameter_name" {
  command = plan

  assert {
    condition     = data.coder_parameter.region.name == "aws_region"
    error_message = "Parameter name should be aws_region"
  }
}

run "custom_order" {
  command = plan

  variables {
    coder_parameter_order = 99
  }

  assert {
    condition     = data.coder_parameter.region.order == 99
    error_message = "coder_parameter_order should propagate to the parameter order"
  }
}

run "default_output" {
  command = apply

  assert {
    condition     = output.value == ""
    error_message = "Default output should be empty when no default is set"
  }
}

run "empty_default_has_no_availability_zone" {
  command = apply

  assert {
    condition     = output.availability_zone == ""
    error_message = "availability_zone should be empty when no region is selected"
  }
}

run "custom_default" {
  command = apply

  variables {
    default = "us-west-2"
  }

  assert {
    condition     = output.value == "us-west-2"
    error_message = "Output should match the configured default"
  }
}

run "availability_zone_for_selected_region" {
  command = apply

  variables {
    default = "us-west-2"
  }

  assert {
    condition     = output.availability_zone == "us-west-2a"
    error_message = "availability_zone should be the selected region's default zone"
  }
}

run "regions_output_exposes_full_catalog" {
  command = plan

  assert {
    condition     = length(output.regions) == length(local.regions)
    error_message = "The regions output should expose every catalog entry keyed by ID"
  }
}

run "regions_output_includes_metadata" {
  command = plan

  assert {
    condition     = output.regions["us-east-1"].name == "US East (N. Virginia)" && output.regions["us-east-1"].availability_zone == "us-east-1a"
    error_message = "regions output should expose name and availability_zone per region"
  }
}

run "exclude_removes_option" {
  command = apply

  variables {
    exclude = ["ap-northeast-2", "ap-northeast-3"]
  }

  assert {
    condition     = !contains([for o in data.coder_parameter.region.option : o.value], "ap-northeast-2") && !contains([for o in data.coder_parameter.region.option : o.value], "ap-northeast-3")
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
    condition     = length([for o in data.coder_parameter.region.option : o if o.value == "ap-south-1" && o.name == "Awesome Mumbai!" && o.icon == "/emojis/1f33a.png"]) == 1
    error_message = "custom_names and custom_icons should override the defaults for a region"
  }
}
