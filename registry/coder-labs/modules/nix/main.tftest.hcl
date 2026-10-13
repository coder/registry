# nixos

run "safe_render" {
  command = plan

  variables {
    nixos = {
      flake_ref  = "git+ssh://git@example.org/flake?ref=feature"
      flake_attr = "host-$ARCH'$(touch /tmp/should-not-run)"
      flake_dir  = "/etc/nixos'$(touch /tmp/should-not-run)"
    }
  }

  assert {
    condition     = output.flake_uri == "ssh://git@example.org/flake?ref=feature#host-x86_64'$(touch /tmp/should-not-run)"
    error_message = "SSH userinfo or reference parsing changed."
  }
  assert {
    condition     = strcontains(output.boot_script, base64encode("/etc/nixos'$(touch /tmp/should-not-run)")) && !strcontains(output.boot_script, "FLAKE_DIR='/etc/nixos'")
    error_message = "The boot script must encode untrusted arguments."
  }
}

run "nixos_defaults" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "coder-workspace-ec2-$ARCH"
      arch       = "aarch64"
    }
  }
  assert {
    condition     = var.nixos.enabled && var.nixos.type == "flake" && !var.develop.enabled
    error_message = "nixos should be enabled with type flake, and develop disabled, by default."
  }
  assert {
    condition     = output.flake_uri == "https://example.org/flake#coder-workspace-ec2-aarch64"
    error_message = "The default branch or ARM attribute changed."
  }
  assert {
    condition     = strcontains(output.boot_script, "nixos-rebuild") && output.flake_dir == "/etc/nixos" && output.log_dir == "/var/log/coder-nixos"
    error_message = "The boot script or default directories changed."
  }
  assert {
    condition     = output.develop_command == null && length(coder_app.develop) == 0
    error_message = "develop outputs must be empty when develop is disabled."
  }
}

run "allow_http_userinfo" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "git+https://user:token@example.org/flake?ref=main"
      flake_attr = "coder-workspace-ec2-$ARCH"
    }
  }
  assert {
    condition     = output.flake_uri == "https://user:token@example.org/flake?ref=main#coder-workspace-ec2-x86_64"
    error_message = "Git URL userinfo should remain available for private clones."
  }
}

run "reject_control_characters" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake?ref=main\nmalicious"
      flake_attr = "host"
    }
  }
  expect_failures = [var.nixos]
}

run "reject_unsupported_query" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake?dir=subdir"
      flake_attr = "host"
    }
  }
  expect_failures = [var.nixos]
}

run "reject_nixos_type_channel" {
  command = plan
  variables {
    nixos = {
      type       = "channel"
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
    }
  }
  expect_failures = [var.nixos]
}

run "require_flake_when_nixos_enabled" {
  command         = plan
  expect_failures = [var.nixos]
}

# develop

run "require_one_enabled" {
  command = plan
  variables {
    nixos   = { enabled = false }
    develop = { enabled = false }
  }
  expect_failures = [var.develop]
}

run "develop_only_without_path" {
  command = plan
  variables {
    nixos   = { enabled = false }
    develop = { enabled = true }
  }
  assert {
    condition     = output.develop_command == "nix --extra-experimental-features 'nix-command flakes' develop '.'"
    error_message = "develop_command without a path should use the current directory."
  }
  assert {
    condition     = length(coder_app.develop) == 0
    error_message = "No app should be created without develop.path."
  }
  assert {
    condition     = output.boot_script == null && output.flake_uri == null && output.version_command == null
    error_message = "nixos outputs must be null when nixos is disabled."
  }
}

run "develop_app_absolute_path" {
  command = plan
  variables {
    agent_id = "agent"
    nixos    = { enabled = false }
    develop = {
      enabled = true
      path    = "/home/coder/it's a project"
      shell   = "ci"
      order   = 3
    }
  }
  assert {
    condition     = coder_app.develop[0].command == "cd '/home/coder/it'\\''s a project' && exec nix --extra-experimental-features 'nix-command flakes' develop '.#ci'"
    error_message = "Unexpected app command: ${coder_app.develop[0].command}"
  }
  assert {
    condition     = coder_app.develop[0].slug == "nix-develop" && coder_app.develop[0].display_name == "Nix Develop" && coder_app.develop[0].order == 3 && coder_app.develop[0].icon == "/icon/nix.svg"
    error_message = "Unexpected app presentation."
  }
  assert {
    condition     = output.develop_command == coder_app.develop[0].command
    error_message = "develop_command should match the app command."
  }
}

run "develop_app_home_relative_path" {
  command = plan
  variables {
    agent_id = "agent"
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
    }
    develop = {
      enabled = true
      path    = "~/project"
    }
  }
  assert {
    condition     = coder_app.develop[0].command == "cd \"$HOME\"/'project' && exec nix --extra-experimental-features 'nix-command flakes' develop '.'"
    error_message = "Unexpected app command: ${coder_app.develop[0].command}"
  }
  assert {
    condition     = output.boot_script != null
    error_message = "nixos and develop should work together."
  }
}

run "develop_app_requires_agent_id" {
  command = plan
  variables {
    nixos = { enabled = false }
    develop = {
      enabled = true
      path    = "project"
    }
  }
  expect_failures = [coder_app.develop]
}
