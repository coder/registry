mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      start_count = 1
      access_url  = "https://coder.example"
    }
  }
}

run "nixos_defaults_and_safe_render" {
  command = plan
  variables {
    nixos = {
      flake_ref   = "git+ssh://git@example.org/flake?ref=feature"
      flake_attr  = "host'$(touch /tmp/should-not-run)"
      flake_dir   = "/etc/nixos'$(touch /tmp/should-not-run)"
      agent_token = "main-token"
      arch        = "amd64"
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
    condition     = strcontains(coder_script.nixos_rebuild[0].script, base64encode(local.rebuild_script)) && strcontains(local.rebuild_script, base64encode(var.nixos.flake_dir)) && !strcontains(local.rebuild_script, "FLAKE_DIR='/etc/nixos'")
    error_message = "The template must encode arguments before inserting them into shell."
  }
  assert {
    condition     = coder_agent.builder[0].arch == "amd64" && coder_agent.builder[0].order == 1 && coder_script.nixos_rebuild[0].run_on_start
    error_message = "The builder agent must match the requested architecture and rebuild on start."
  }
}

# The agent socket ignores TMPDIR. A root socket in /tmp blocks the main agent.
run "builder_socket_path" {
  command = apply
  variables {
    nixos = {
      flake_ref   = "https://example.org/flake"
      flake_attr  = "host"
      agent_token = "main-token"
      arch        = "amd64"
    }
  }
  assert {
    condition     = strcontains(nonsensitive(output.boot_script), "CODER_AGENT_SOCKET_PATH=\"$BUILDER_TMP/coder-agent.sock\"")
    error_message = "The builder agent socket must not use the main agent's default path."
  }
}

run "reject_root_flake_dir" {
  command = plan
  variables {
    nixos = { flake_ref = "https://example.org/flake", flake_attr = "host", agent_token = "t", arch = "amd64", flake_dir = "/etc/.." }
  }
  expect_failures = [var.nixos]
}

run "require_flake_when_nixos_enabled" {
  command = plan
  variables {
    nixos = { agent_token = "t", arch = "amd64" }
  }
  expect_failures = [var.nixos]
}

run "stopped_workspace_needs_no_token" {
  command = plan
  override_data {
    target = data.coder_workspace.me
    values = { start_count = 0 }
  }
  variables {
    nixos = { flake_ref = "https://example.org/flake", flake_attr = "host", agent_token = "", arch = "amd64" }
  }
  assert {
    condition     = length(coder_agent.builder) == 0 && length(coder_script.nixos_rebuild) == 0 && nonsensitive(output.boot_script) == ""
    error_message = "A stopped workspace must not create the builder agent or a boot script."
  }
}

run "require_agent_token_when_nixos_enabled" {
  command = plan
  variables {
    nixos = { flake_ref = "https://example.org/flake", flake_attr = "host", arch = "amd64" }
  }
  expect_failures = [var.nixos]
}

run "require_arch_when_nixos_enabled" {
  command = plan
  variables {
    nixos = { flake_ref = "https://example.org/flake", flake_attr = "host", agent_token = "t", arch = "x86_64" }
  }
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
    condition     = output.boot_script == "" && output.builder_agent_id == null && output.flake_uri == null && output.log_dir == null && length(coder_agent.builder) == 0
    error_message = "NixOS outputs must be null when disabled."
  }
}

run "develop_with_nixos_no_prebuild" {
  command = plan
  variables {
    agent_id = "agent"
    nixos    = { flake_ref = "https://example.org/flake", flake_attr = "host", agent_token = "t", arch = "arm64" }
    develop  = { enabled = true, path = "~/project", prebuild = false }
  }
  assert {
    condition     = coder_app.develop[0].slug == "nix-develop" && length(coder_agent.builder) == 1 && output.scripts == []
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
      agent_token     = "t"
      arch            = "amd64"
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
    condition     = strcontains(local.rebuild_script, base64encode("extra-experimental-features = ca-derivations\nextra-substituters = https://cache.example.org https://cache2.example.org\nextra-trusted-public-keys = cache.example.org-1:AbC=\nmax-jobs = auto\nsandbox = true\nextra-experimental-features = nix-command flakes"))
    error_message = "The rebuild script must carry the NixOS settings and its overrides."
  }
}
