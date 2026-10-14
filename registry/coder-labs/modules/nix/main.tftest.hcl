run "nixos_defaults_and_safe_render" {
  command = plan
  variables {
    nixos = {
      flake_ref  = "git+ssh://git@example.org/flake?ref=feature"
      flake_attr = "host'$(touch /tmp/should-not-run)"
      flake_dir  = "/etc/nixos'$(touch /tmp/should-not-run)"
    }
  }
  assert {
    condition     = var.nixos.enabled && !var.develop.enabled && length(coder_app.develop) == 0 && output.scripts == []
    error_message = "Only nixos should be enabled by default."
  }
  assert {
    condition     = output.flake_uri == "ssh://git@example.org/flake?ref=feature#host'$(touch /tmp/should-not-run)" && output.log_dir == "/var/log/coder-nixos"
    error_message = "Unexpected flake reference or log directory."
  }
  assert {
    condition     = strcontains(output.boot_script, base64encode(var.nixos.flake_dir)) && !strcontains(output.boot_script, "FLAKE_DIR='/etc/nixos'")
    error_message = "The template must encode arguments before inserting them into shell."
  }
}

run "reject_root_flake_dir" {
  command = plan
  variables {
    nixos = { flake_ref = "https://example.org/flake", flake_attr = "host", flake_dir = "/etc/.." }
  }
  expect_failures = [var.nixos]
}

run "require_flake_when_nixos_enabled" {
  command         = plan
  expect_failures = [var.nixos]
}

run "require_one_enabled" {
  command = plan
  variables {
    nixos   = { enabled = false }
    develop = { enabled = false }
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
    condition     = startswith(coder_app.develop[0].command, "#!/usr/bin/env bash\n") && strcontains(coder_app.develop[0].command, "cd \"$HOME/it's a project\"") && strcontains(coder_app.develop[0].command, base64encode(".#ci"))
    error_message = "The app must run Bash, use the path as written, and select the requested shell."
  }
  assert {
    condition     = coder_app.develop[0].slug == "dev-shell" && coder_app.develop[0].order == 3 && length(output.scripts) == 1
    error_message = "App customization and default prebuild should be honored."
  }
  assert {
    condition     = coder_env.path[0].name == "PATH" && coder_env.path[0].merge_strategy == "append" && coder_env.path[0].value == "$PATH:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin"
    error_message = "The module should extend the workspace PATH with both Nix profiles."
  }
  assert {
    condition     = output.boot_script == null && output.flake_uri == null && output.log_dir == null && output.version_command == null
    error_message = "NixOS outputs must be null when disabled."
  }
}

run "develop_with_nixos_no_prebuild" {
  command = plan
  variables {
    agent_id = "agent"
    nixos    = { flake_ref = "https://example.org/flake", flake_attr = "host" }
    develop  = { enabled = true, path = "~/project", prebuild = false }
  }
  assert {
    condition     = coder_app.develop[0].slug == "nix-develop" && output.boot_script != null && output.scripts == []
    error_message = "Both modes should work together without prebuild."
  }
}

run "config_merge_and_render" {
  command = plan
  variables {
    agent_id = "agent"
    config = {
      extra-experimental-features = ["ca-derivations"]
      extra-substituters          = ["https://cache.example.org", "https://cache2.example.org"]
      extra-trusted-public-keys   = ["cache.example.org-1:AbC="]
      max-jobs                    = 4
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
    condition     = coder_env.nix_config[0].name == "NIX_CONFIG" && coder_env.nix_config[0].value == "extra-experimental-features = ca-derivations\nextra-substituters = https://cache.example.org https://cache2.example.org\nextra-trusted-public-keys = cache.example.org-1:AbC=\nkeep-outputs = true\nmax-jobs = 4\nextra-experimental-features = nix-command flakes"
    error_message = "Develop settings must merge per key, preserve trust settings, and append required features."
  }
  assert {
    condition     = strcontains(output.boot_script, base64encode("extra-experimental-features = ca-derivations\nextra-substituters = https://cache.example.org https://cache2.example.org\nextra-trusted-public-keys = cache.example.org-1:AbC=\nmax-jobs = auto\nsandbox = true\nextra-experimental-features = nix-command flakes"))
    error_message = "The boot script must carry the NixOS settings and its overrides."
  }
}
