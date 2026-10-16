variables {
  agent_id       = "test-agent"
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
}

run "defaults_are_correct" {
  command = plan

  assert {
    condition     = var.install_goose == true
    error_message = "install_goose should default to true"
  }

  assert {
    condition     = var.goose_version == "stable"
    error_message = "goose_version should default to 'stable'"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder/goose"
    error_message = "module_dir_name should be '.coder-modules/coder/goose'"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("stable"))
    error_message = "install script should receive the goose version"
  }

  assert {
    condition     = local.combined_extensions == "extensions:\n  developer:\n    display_name: Developer\n    enabled: true\n    name: developer\n    timeout: 300\n    type: builtin\n"
    error_message = "config should only contain the developer extension by default"
  }
}

run "workdir_trailing_slash_is_trimmed" {
  command = plan

  variables {
    workdir = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should have its trailing slash trimmed"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("/home/coder/project"))
    error_message = "install script should receive the base64-encoded workdir"
  }
}

run "additional_extensions_are_appended" {
  command = plan

  variables {
    additional_extensions = <<-EOT
      everything:
        name: everything
        type: stdio
    EOT
  }

  assert {
    condition     = strcontains(local.combined_extensions, "    type: builtin\n  everything:\n    name: everything\n    type: stdio\n")
    error_message = "additional_extensions should be appended after the developer extension"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(local.combined_extensions))
    error_message = "install script should receive the combined extensions"
  }
}

run "pinned_goose_version_is_passed" {
  command = plan

  variables {
    goose_version = "v1.53.0"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("v1.53.0"))
    error_message = "install script should receive the pinned goose version"
  }
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-goose-pre_install_script", "coder-goose-install_script", "coder-goose-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  assert {
    condition     = output.scripts == ["coder-goose-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
