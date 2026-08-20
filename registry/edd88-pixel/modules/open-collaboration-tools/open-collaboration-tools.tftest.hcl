run "defaults" {
  command = plan

  variables {
    server_url = "https://oct.example.com"
  }

  assert {
    condition     = tolist(output.extensions) == tolist(["typefox.open-collaboration-tools@0.3.9"])
    error_message = "The official OCT extension version should be installed by default."
  }

  assert {
    condition     = output.settings["oct.serverUrl"] == "https://oct.example.com/"
    error_message = "The server URL should have one trailing slash."
  }

  assert {
    condition     = output.settings["oct.joinAcceptMode"] == "prompt"
    error_message = "Join requests should require host confirmation by default."
  }

  assert {
    condition     = tolist(output.settings["oct.files.exclude"]) == tolist(["**/.env"])
    error_message = "Environment files should be excluded by default."
  }
}

run "normalizes_trailing_slash" {
  command = plan

  variables {
    server_url = "https://oct.example.com/"
  }

  assert {
    condition     = output.settings["oct.serverUrl"] == "https://oct.example.com/"
    error_message = "The normalized server URL should contain one trailing slash."
  }
}

run "supports_local_http_server" {
  command = plan

  variables {
    server_url = "http://127.0.0.1:8100"
  }

  assert {
    condition     = output.settings["oct.serverUrl"] == "http://127.0.0.1:8100/"
    error_message = "Local development servers should support HTTP."
  }
}

run "rejects_remote_http_server" {
  command = plan

  variables {
    server_url = "http://oct.example.com"
  }

  expect_failures = [var.server_url]
}

run "rejects_invalid_extension_id" {
  command = plan

  variables {
    server_url   = "https://oct.example.com"
    extension_id = "open-collaboration-tools"
  }

  expect_failures = [var.extension_id]
}

run "rejects_invalid_extension_version" {
  command = plan

  variables {
    server_url        = "https://oct.example.com"
    extension_version = "latest"
  }

  expect_failures = [var.extension_version]
}

run "supports_preinstalled_extension" {
  command = plan

  variables {
    server_url        = "https://oct.example.com"
    install_extension = false
  }

  assert {
    condition     = length(output.extensions) == 0
    error_message = "No extension should be installed when it is already present in the image."
  }
}

run "supports_allowlist_mode" {
  command = plan

  variables {
    server_url       = "https://oct.example.com"
    join_accept_mode = "allowlist"
    join_allowlist   = ["alice", "bob"]
  }

  assert {
    condition     = output.settings["oct.joinAcceptMode"] == "allowlist"
    error_message = "The allowlist join policy should be preserved."
  }

  assert {
    condition     = tolist(output.settings["oct.joinAllowlist"]) == tolist(["alice", "bob"])
    error_message = "The configured join allowlist should be preserved."
  }
}

run "supports_automatic_mode" {
  command = plan

  variables {
    server_url       = "https://oct.example.com"
    join_accept_mode = "auto"
  }

  assert {
    condition     = output.settings["oct.joinAcceptMode"] == "auto"
    error_message = "The automatic join policy should be preserved."
  }
}

run "rejects_invalid_join_mode" {
  command = plan

  variables {
    server_url       = "https://oct.example.com"
    join_accept_mode = "unrestricted"
  }

  expect_failures = [var.join_accept_mode]
}

run "rejects_empty_list_entries" {
  command = plan

  variables {
    server_url     = "https://oct.example.com"
    join_allowlist = ["alice", " "]
    excluded_files = ["**/.env", ""]
  }

  expect_failures = [var.join_allowlist, var.excluded_files]
}
