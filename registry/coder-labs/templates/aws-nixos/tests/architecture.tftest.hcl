mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      name        = "test"
      start_count = 1
      transition  = "start"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      name      = "owner"
      full_name = "Owner"
      email     = "owner@example.org"
    }
  }
  mock_data "coder_parameter" {
    defaults = {
      value = "80"
    }
  }
}

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id   = "ami-example"
      name = "nixos/latest"
    }
  }
}

mock_provider "http" {}

override_module {
  target = module.aws-region
  outputs = {
    value                     = "eu-west-3"
    default_availability_zone = "eu-west-3a"
  }
}

override_module {
  target = module.aws-ec2-instance-type
  outputs = {
    value = "t3.medium"
    instances = {
      "t3.medium"  = { arch = "x86_64", coder_arch = "amd64" }
      "t4g.medium" = { arch = "arm64", coder_arch = "arm64" }
    }
  }
}

override_module {
  target  = module.code-server
  outputs = {}
}
override_module {
  target  = module.jetbrains-gateway
  outputs = {}
}
override_module {
  target  = module.git-config
  outputs = {}
}

run "x86" {
  command = plan
  assert {
    condition     = local.nix_arch == "x86_64" && coder_agent.main[0].arch == "amd64" && local.flake_attr == "coder-workspace-ec2-x86_64"
    error_message = "The x86 instance, agent and flake attribute must agree."
  }
  assert {
    condition     = coder_agent.provisioner[0].arch == "amd64" && coder_agent.provisioner[0].order > coder_agent.main[0].order
    error_message = "The provisioner agent must match the instance and sort after the main agent."
  }
  assert {
    condition     = coder_metadata.provisioner[0].hide && coder_script.nixos_rebuild[0].run_on_start
    error_message = "The provisioner must be hidden and rebuild on start."
  }
  assert {
    condition     = aws_instance.dev.ami == "ami-example" && coder_metadata.workspace_info.item[0].value == aws_instance.dev.ami
    error_message = "AMI metadata must show the instance's actual AMI ID."
  }
}

run "arm" {
  command = plan
  override_module {
    target = module.aws-ec2-instance-type
    outputs = {
      value = "t4g.medium"
      instances = {
        "t3.medium"  = { arch = "x86_64", coder_arch = "amd64" }
        "t4g.medium" = { arch = "arm64", coder_arch = "arm64" }
      }
    }
  }
  assert {
    condition     = local.nix_arch == "aarch64" && coder_agent.main[0].arch == "arm64" && local.flake_attr == "coder-workspace-ec2-aarch64"
    error_message = "The ARM instance, agent and flake attribute must agree."
  }
  assert {
    condition     = coder_agent.provisioner[0].arch == "arm64"
    error_message = "The provisioner agent must match the ARM instance."
  }
}

run "stop" {
  command = plan
  override_data {
    target = data.coder_workspace.me
    values = {
      name        = "test"
      start_count = 0
      transition  = "stop"
    }
  }
  assert {
    condition     = length(coder_agent.main) == 0 && length(coder_agent.provisioner) == 0 && length(terraform_data.provisioner) == 0 && aws_ec2_instance_state.dev.state == "stopped"
    error_message = "Stopping must remove both agents and stop, not destroy, the EC2 instance."
  }
}
