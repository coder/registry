mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      name      = "Owner"
      full_name = "Owner"
      email     = "owner@example.org"
    }
  }
  mock_data "coder_parameter" {
    defaults = {
      value = "4"
    }
  }
}

mock_provider "incus" {}

mock_provider "random" {}

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
    condition     = local.nix_arch == "x86_64" && coder_agent.main[0].arch == "amd64" && local.flake_attr == "coder-workspace-incus-x86_64"
    error_message = "The x86 host, agent and flake attribute must agree."
  }
  assert {
    condition     = incus_instance.dev.image == "images:nixos/26.05" && incus_instance.dev.type == "virtual-machine" && incus_instance.dev.running
    error_message = "A started workspace must be a running NixOS VM."
  }
  assert {
    condition     = incus_instance.dev.name == "coder-owner-test"
    error_message = "Instance names must be lowercase."
  }
  assert {
    condition     = contains(keys(incus_instance.dev.exec), "coder-init")
    error_message = "A start must run the bootstrap."
  }
}

run "arm" {
  command = plan
  variables {
    arch = "arm64"
  }
  assert {
    condition     = local.nix_arch == "aarch64" && coder_agent.main[0].arch == "arm64" && local.flake_attr == "coder-workspace-incus-aarch64"
    error_message = "The ARM host, agent and flake attribute must agree."
  }
}

run "storage_pool_override" {
  command = plan
  variables {
    storage_pool = "fast"
  }
  assert {
    condition     = local.storage_pool == "fast"
    error_message = "storage_pool must override the profile's pool."
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
    condition     = length(coder_agent.main) == 0 && !incus_instance.dev.running && length(incus_instance.dev.exec) == 0
    error_message = "Stopping must remove the agent and stop, not destroy, the VM."
  }
}

run "reject_arch" {
  command = plan
  variables {
    arch = "riscv64"
  }
  expect_failures = [var.arch]
}
