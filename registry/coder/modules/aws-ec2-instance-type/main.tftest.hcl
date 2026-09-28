run "parameter_name" {
  command = plan

  assert {
    condition     = data.coder_parameter.instance_type[0].name == "aws_ec2_instance_type"
    error_message = "Parameter name should be aws_ec2_instance_type"
  }
}

run "custom_order" {
  command = plan

  variables {
    coder_parameter_order = 99
  }

  assert {
    condition     = data.coder_parameter.instance_type[0].order == 99
    error_message = "coder_parameter_order should propagate to the parameter order"
  }
}

run "default_output" {
  command = apply

  assert {
    condition     = output.value == ""
    error_message = "value should be empty when no default is set"
  }
}

run "custom_default" {
  command = apply

  variables {
    default = "t3.large"
  }

  assert {
    condition     = output.value == "t3.large"
    error_message = "value should match the configured default"
  }
}

run "disabling_parameter_skips_creation" {
  command = apply

  variables {
    create_parameter = false
    default          = "t4g.large"
  }

  assert {
    condition     = length(data.coder_parameter.instance_type) == 0
    error_message = "No coder_parameter should be created when create_parameter is false"
  }

  assert {
    condition     = output.value == "t4g.large"
    error_message = "value should fall back to default when the parameter is disabled"
  }
}

run "default_include_covers_template_types" {
  command = apply

  assert {
    condition = alltrue([
      for v in ["t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge"] :
      contains([for o in data.coder_parameter.instance_type[0].option : o.value], v)
    ])
    error_message = "The default t3 family must include every instance type used by the AWS templates"
  }
}

run "include_filters_by_family" {
  command = apply

  variables {
    include = ["c5"]
  }

  assert {
    condition     = contains([for o in data.coder_parameter.instance_type[0].option : o.value], "c5.large") && !contains([for o in data.coder_parameter.instance_type[0].option : o.value], "t3.micro")
    error_message = "include should show the requested family and hide others"
  }
}

run "include_allows_multiple_families" {
  command = apply

  variables {
    include = ["t3", "c5"]
  }

  assert {
    condition     = contains([for o in data.coder_parameter.instance_type[0].option : o.value], "t3.micro") && contains([for o in data.coder_parameter.instance_type[0].option : o.value], "c5.large") && !contains([for o in data.coder_parameter.instance_type[0].option : o.value], "m5.large")
    error_message = "include should accept multiple families and exclude the rest"
  }

  assert {
    condition     = length([for o in data.coder_parameter.instance_type[0].option : o if o.value == "c5.large" && o.name == "2 vCPU, 4 GiB RAM (amd64, c5.large)"]) == 1
    error_message = "a spec label shared across families should be disambiguated with the instance type"
  }

  assert {
    condition     = length([for o in data.coder_parameter.instance_type[0].option : o if o.value == "t3.large" && o.name == "2 vCPU, 8 GiB RAM (amd64)"]) == 1
    error_message = "a unique spec label should stay specs-only"
  }
}

run "option_name_is_specs_and_tooltip_is_instance_type" {
  command = apply

  assert {
    condition     = length([for o in data.coder_parameter.instance_type[0].option : o if o.value == "t3.medium" && o.name == "2 vCPU, 4 GiB RAM (amd64)" && o.description == "t3.medium"]) == 1
    error_message = "Option name should be the computed specs with arch and the description should be the instance type"
  }
}

run "custom_names_and_descriptions_override" {
  command = apply

  variables {
    custom_names        = { "t3.medium" = "Standard" }
    custom_descriptions = { "t3.medium" = "custom" }
  }

  assert {
    condition     = length([for o in data.coder_parameter.instance_type[0].option : o if o.value == "t3.medium" && o.name == "Standard" && o.description == "custom"]) == 1
    error_message = "custom_names and custom_descriptions should override the option name and description"
  }
}

run "instances_output_exposes_specs_and_derived_fields" {
  command = plan

  assert {
    condition     = length(output.instances) == length(local.instance_types)
    error_message = "The instances output should expose every catalog entry keyed by value"
  }

  assert {
    condition     = output.instances["t3.medium"].vcpus == 2 && output.instances["t3.medium"].memory_mib == 4096 && output.instances["t3.medium"].gpus == 0
    error_message = "Raw specs should be exposed as numeric fields"
  }

  assert {
    condition     = output.instances["t3.medium"].coder_arch == "amd64" && output.instances["t3.medium"].ami == "x86_64"
    error_message = "x86 instances should derive amd64 from the x86_64 AMI arch"
  }

  assert {
    condition     = output.instances["m7g.large"].coder_arch == "arm64" && output.instances["m7g.large"].ami == "arm64"
    error_message = "Graviton instances should derive arm64"
  }

  assert {
    condition     = output.instances["g4dn.12xlarge"].gpus == 4
    error_message = "gpus should reflect the source data"
  }
}

run "value_is_key_in_instances" {
  command = apply

  variables {
    include = ["t4g"]
    default = "t4g.medium"
  }

  assert {
    condition     = contains(keys(output.instances), output.value) && output.instances[output.value].coder_arch == "arm64"
    error_message = "The selected value must be a key in the instances output"
  }
}
