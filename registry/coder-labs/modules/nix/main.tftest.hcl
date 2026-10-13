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
    condition     = var.nixos.enabled && !var.develop.enabled
    error_message = "nixos should be enabled, and develop disabled, by default."
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

run "reject_relative_or_root_dirs" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
      flake_dir  = "/"
    }
  }
  expect_failures = [var.nixos]
}

run "reject_noncanonical_dir" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
      log_dir    = "/var/log/../log/x/"
    }
  }
  expect_failures = [var.nixos]
}

run "reject_empty_flake_attr" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = ""
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
    agent_id = "agent"
    nixos    = { enabled = false }
    develop  = { enabled = false, path = "project" }
  }
  expect_failures = [var.develop]
}

run "require_path_when_develop_enabled" {
  command = plan
  variables {
    agent_id = "agent"
    nixos    = { enabled = false }
    develop  = { enabled = true }
  }
  expect_failures = [var.develop]
}

run "develop_requires_agent_id" {
  command = plan
  variables {
    nixos   = { enabled = false }
    develop = { enabled = true, path = "project" }
  }
  expect_failures = [var.develop]
}

run "develop_app_script" {
  command = plan
  variables {
    agent_id = "agent"
    nixos    = { enabled = false }
    develop = {
      enabled = true
      path    = "\"$HOME/it's a project\""
      shell   = "ci"
      slug    = "dev-shell"
      order   = 3
    }
  }
  assert {
    condition     = startswith(coder_app.develop[0].command, "#!/usr/bin/env bash\n")
    error_message = "The app must run under bash, whatever the user's shell is."
  }
  assert {
    condition     = strcontains(coder_app.develop[0].command, "\nPROJECT_PATH=\"$HOME/it's a project\"\n")
    error_message = "develop.path must be inserted as written."
  }
  assert {
    condition     = strcontains(coder_app.develop[0].command, base64encode(".#ci")) && strcontains(coder_app.develop[0].command, "/.nix-profile/etc/profile.d/nix.sh")
    error_message = "The app should select the shell and find nix like the prebuild does."
  }
  assert {
    condition     = coder_app.develop[0].slug == "dev-shell" && coder_app.develop[0].display_name == "Nix Develop" && coder_app.develop[0].order == 3 && coder_app.develop[0].icon == "/icon/nix.svg"
    error_message = "Unexpected app presentation."
  }
  assert {
    condition     = output.develop_command == coder_app.develop[0].command
    error_message = "develop_command should match the app command."
  }
  assert {
    condition     = output.boot_script == null && output.flake_uri == null && output.version_command == null && output.nixos_nix_conf == null
    error_message = "nixos outputs must be null when nixos is disabled."
  }
  assert {
    condition     = length(output.scripts) == 1 && length(coder_env.nix_config) == 0
    error_message = "prebuild should be on by default, and no NIX_CONFIG is exported without settings."
  }
}

run "develop_with_nixos_no_prebuild" {
  command = plan
  variables {
    agent_id = "agent"
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
    }
    develop = {
      enabled  = true
      path     = "~/project"
      prebuild = false
    }
  }
  assert {
    condition     = coder_app.develop[0].slug == "nix-develop" && strcontains(coder_app.develop[0].command, "\nPROJECT_PATH=~/project\n")
    error_message = "Unexpected default slug or path handling."
  }
  assert {
    condition     = output.boot_script != null && output.scripts == []
    error_message = "nixos and develop should work together, and prebuild = false should create no scripts."
  }
}

# nix.conf settings

run "config_merge_and_render" {
  command = plan
  variables {
    agent_id = "agent"
    config = {
      extra-substituters        = ["https://cache.example.org", "https://cache2.example.org"]
      extra-trusted-public-keys = ["cache.example.org-1:AbC="]
      max-jobs                  = 4
    }
    nixos = {
      flake_ref       = "https://example.org/flake"
      flake_attr      = "host"
      config_override = { max-jobs = "auto", sandbox = true }
    }
    develop = {
      enabled         = true
      path            = "project"
      config_override = { keep-outputs = true }
    }
  }
  assert {
    condition     = output.nixos_nix_conf == "extra-substituters = https://cache.example.org https://cache2.example.org\nextra-trusted-public-keys = cache.example.org-1:AbC=\nmax-jobs = auto\nsandbox = true"
    error_message = "Unexpected nixos_nix_conf: ${output.nixos_nix_conf}"
  }
  assert {
    condition     = output.develop_nix_conf == "extra-substituters = https://cache.example.org https://cache2.example.org\nkeep-outputs = true\nmax-jobs = 4"
    error_message = "develop should get shared settings and its override, but not daemon-only keys while nixos is enabled: ${output.develop_nix_conf}"
  }
  assert {
    condition     = strcontains(output.boot_script, base64encode(output.nixos_nix_conf))
    error_message = "The boot script must carry the nixos settings."
  }
  assert {
    condition     = coder_env.nix_config[0].name == "NIX_CONFIG" && coder_env.nix_config[0].value == output.develop_nix_conf
    error_message = "NIX_CONFIG should be exported with the develop settings."
  }
  assert {
    condition     = strcontains(coder_app.develop[0].command, "NIX_CONF=$(printf %s '' | base64 -d)")
    error_message = "The app must not re-append settings that coder_env already exports."
  }
}

run "config_example_exact_value" {
  command = plan
  variables {
    agent_id = "agent"
    config = {
      extra-substituters        = ["https://cache.example.org"]
      extra-trusted-public-keys = ["cache.example.org-1:AbC="]
    }
    nixos = {
      flake_ref  = "https://example.org/flake"
      flake_attr = "host"
    }
    develop = {
      enabled         = true
      path            = "project"
      config_override = { keep-outputs = true }
    }
  }
  assert {
    condition     = coder_env.nix_config[0].value == "extra-substituters = https://cache.example.org\nkeep-outputs = true"
    error_message = "Unexpected NIX_CONFIG: ${coder_env.nix_config[0].value}"
  }
}

run "develop_keeps_trusted_keys_without_nixos" {
  command = plan
  variables {
    agent_id = "agent"
    config   = { extra-trusted-public-keys = ["k1"] }
    nixos    = { enabled = false }
    develop  = { enabled = true, path = "project" }
  }
  assert {
    condition     = output.develop_nix_conf == "extra-trusted-public-keys = k1"
    error_message = "Without nixos, the client must get every setting."
  }
}

run "export_config_false_inlines_settings" {
  command = plan
  variables {
    agent_id = "agent"
    config   = { keep-outputs = true }
    nixos    = { enabled = false }
    develop  = { enabled = true, path = "/p", export_config = false }
  }
  assert {
    condition     = length(coder_env.nix_config) == 0
    error_message = "export_config = false must not export NIX_CONFIG."
  }
  assert {
    condition     = strcontains(coder_app.develop[0].command, "NIX_CONF=$(printf %s '${base64encode("keep-outputs = true")}' | base64 -d)")
    error_message = "Unexpected app command: ${coder_app.develop[0].command}"
  }
}

run "reject_bad_config_key" {
  command = plan
  variables {
    config = { "Bad Key" = "x" }
    nixos  = { flake_ref = "https://example.org/flake", flake_attr = "host" }
  }
  expect_failures = [var.config]
}

run "reject_config_newline" {
  command = plan
  variables {
    config = { extra-substituters = ["https://a\nb"] }
    nixos  = { flake_ref = "https://example.org/flake", flake_attr = "host" }
  }
  expect_failures = [var.config]
}

run "reject_config_object_value" {
  command = plan
  variables {
    config = { foo = { a = "b" } }
    nixos  = { flake_ref = "https://example.org/flake", flake_attr = "host" }
  }
  expect_failures = [var.config]
}

run "reject_bad_override_key" {
  command = plan
  variables {
    nixos = {
      flake_ref       = "https://example.org/flake"
      flake_attr      = "host"
      config_override = { "!include" = "/etc/passwd" }
    }
  }
  expect_failures = [var.nixos]
}
