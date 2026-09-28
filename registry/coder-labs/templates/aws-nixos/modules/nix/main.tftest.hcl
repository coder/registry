run "safe_render" {
  command = plan

  variables {
    flake_ref  = "git+ssh://git@example.org/flake?ref=feature"
    flake_attr = "host-$ARCH'$(touch /tmp/should-not-run)"
    flake_dir  = "/etc/nixos'$(touch /tmp/should-not-run)"
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

run "default_branch" {
  command = plan
  variables {
    flake_ref = "https://example.org/flake"
    arch      = "aarch64"
  }
  assert {
    condition     = output.flake_uri == "https://example.org/flake#coder-workspace-ec2-aarch64"
    error_message = "The default branch or ARM attribute changed."
  }
}

run "reject_http_userinfo" {
  command = plan
  variables {
    flake_ref = "git+https://user:token@example.org/flake?ref=main"
  }
  expect_failures = [var.flake_ref]
}

run "reject_control_characters" {
  command = plan
  variables {
    flake_ref = "https://example.org/flake?ref=main\nmalicious"
  }
  expect_failures = [var.flake_ref]
}

run "reject_unsupported_query" {
  command = plan
  variables {
    flake_ref = "https://example.org/flake?dir=subdir"
  }
  expect_failures = [var.flake_ref]
}
