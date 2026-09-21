run "parameter_name" {
  command = plan

  assert {
    condition     = data.coder_parameter.instance_type.name == "aws_ec2_instance_type"
    error_message = "Parameter name should be aws_ec2_instance_type"
  }
}

run "custom_order" {
  command = plan

  variables {
    coder_parameter_order = 99
  }

  assert {
    condition     = data.coder_parameter.instance_type.order == 99
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

run "custom_default" {
  command = apply

  variables {
    default = "t3.large"
  }

  assert {
    condition     = output.value == "t3.large"
    error_message = "Output should match the configured default"
  }
}

run "default_from_selected_category" {
  command = apply

  variables {
    default       = "c5.9xlarge"
    type_category = ["compute"]
  }

  assert {
    condition     = output.value == "c5.9xlarge"
    error_message = "A default from the selected category should be honored"
  }
}

run "general_category_includes_template_types" {
  command = apply

  assert {
    condition = alltrue([
      for v in ["t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge"] :
      contains([for o in data.coder_parameter.instance_type.option : o.value], v)
    ])
    error_message = "The general category must include every instance type used by the AWS templates"
  }
}

run "type_category_filters_options" {
  command = apply

  variables {
    type_category = ["compute"]
  }

  assert {
    condition     = contains([for o in data.coder_parameter.instance_type.option : o.value], "c5.large") && !contains([for o in data.coder_parameter.instance_type.option : o.value], "t3.micro")
    error_message = "type_category should include compute types and exclude others"
  }
}

run "exclude_removes_option" {
  command = apply

  variables {
    exclude = ["t3.nano"]
  }

  assert {
    condition     = !contains([for o in data.coder_parameter.instance_type.option : o.value], "t3.nano")
    error_message = "Excluded instance types should not appear as options"
  }
}

run "instances_output_exposes_full_catalog" {
  command = plan

  assert {
    condition     = length(output.instances) == length(local.instance_types)
    error_message = "The instances output should expose every catalog entry keyed by value"
  }
}

run "x86_instances_report_amd64" {
  command = plan

  assert {
    condition     = output.instances["t3.medium"].coder_arch == "amd64" && output.instances["t3.medium"].ami == "x86_64" && output.instances["t3.medium"].attr == "x86_64"
    error_message = "x86 instances should report amd64 / x86_64 architecture"
  }
}

run "arm_instances_report_arm64" {
  command = plan

  assert {
    condition     = output.instances["m7g.large"].coder_arch == "arm64" && output.instances["m7g.large"].ami == "arm64" && output.instances["m7g.large"].attr == "aarch64"
    error_message = "Graviton instances should report arm64 / aarch64 architecture"
  }
}

run "value_is_key_in_instances" {
  command = apply

  variables {
    default = "t4g.medium"
  }

  assert {
    condition     = contains(keys(output.instances), output.value) && output.instances[output.value].coder_arch == "arm64"
    error_message = "The selected value must be a key in the instances output"
  }
}
