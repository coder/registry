# Native Terraform tests. Plan-only: no apply, no provider mutation.
# mock_provider keeps everything local; nothing reaches a Coder deployment.
# Requires Terraform >= 1.7 for mock_provider support.

mock_provider "coder" {}

variables {
  subagent_id       = "11111111-1111-1111-1111-111111111111"
  start_count       = 1
  deployment_origin = "https://coder.example.com"
  workspace_id      = "33333333-3333-3333-3333-333333333333"
  config_path       = "/home/coder/repo/.devcontainer/devcontainer.json"
  workspace_folder  = "/home/coder/repo"
  helper_slug       = "orrisdev"
}

run "launcher_url_encodes_all_fields" {
  command = plan

  assert {
    condition = output.launcher_url == join("", [
      "orrisdev://coder/open?deployment=", "https%3A%2F%2Fcoder.example.com",
      "&workspace=", "33333333-3333-3333-3333-333333333333",
      "&config=", "%2Fhome%2Fcoder%2Frepo%2F.devcontainer%2Fdevcontainer.json",
      "&folder=", "%2Fhome%2Fcoder%2Frepo",
      "&app=", "orrisdev",
    ])
    error_message = "Launcher URL must carry exactly the five encoded fields and nothing else."
  }

  assert {
    condition     = output.helper_slug == "orrisdev"
    error_message = "Helper slug output must match the configured helper slug."
  }

  assert {
    condition     = output.open_slug == "open-in-orrisdev"
    error_message = "Launcher slug output must match the default open slug."
  }
  assert {
    condition     = coder_app.orrisdev_helper[0].agent_id == var.subagent_id && coder_app.open_in_orrisdev[0].agent_id == var.subagent_id
    error_message = "Both apps must attach to the exact selected nested agent."
  }
  assert {
    condition     = coder_app.orrisdev_helper[0].share == "owner" && coder_app.orrisdev_helper[0].subdomain && !coalesce(coder_app.orrisdev_helper[0].external, false) && coder_app.open_in_orrisdev[0].external
    error_message = "The helper stays private/subdomain/non-external and the launcher stays external."
  }
  assert {
    condition     = coder_app.open_in_orrisdev[0].url == output.launcher_url && coder_app.orrisdev_helper[0].url == "https://localhost:8443"
    error_message = "Outputs must describe the actual app resources."
  }
}

run "reserved_characters_encode_once" {
  command = plan
  variables {
    config_path      = "/repo/a +&?#/devcontainer.json"
    workspace_folder = "/repo/a +&?#"
  }
  assert {
    condition     = strcontains(output.launcher_url, "&folder=%2Frepo%2Fa+%2B%26%3F%23")
    error_message = "Spaces, literal plus and reserved query characters must encode distinctly."
  }
}

run "rejects_origin_credentials" {
  command = plan
  variables { deployment_origin = "https://user:password@coder.example.com" }
  expect_failures = [var.deployment_origin]
}

run "rejects_invalid_origin_port" {
  command = plan
  variables { deployment_origin = "https://coder.example.com:99999" }
  expect_failures = [var.deployment_origin]
}

run "rejects_duplicate_slugs" {
  command = plan
  variables { open_slug = "orrisdev" }
  expect_failures = [coder_app.open_in_orrisdev]
}

run "rejects_control_character_path" {
  command = plan
  variables { config_path = "/repo/\n/devcontainer.json" }
  expect_failures = [var.config_path]
}

run "rejects_unicode_byte_overflow" {
  command = plan
  variables { workspace_folder = "/${join("", [for i in range(1024) : "éé"])}" }
  expect_failures = [var.workspace_folder]
}

run "stopped_workspace_has_no_apps" {
  command = plan
  variables { start_count = 0 }
  assert {
    condition     = length(coder_app.orrisdev_helper) == 0 && length(coder_app.open_in_orrisdev) == 0
    error_message = "A stopped workspace must register no apps."
  }
}

run "rejects_non_https_origin" {
  command = plan

  variables {
    deployment_origin = "http://coder.example.com"
  }

  expect_failures = [var.deployment_origin]
}

run "rejects_origin_with_path" {
  command = plan

  variables {
    deployment_origin = "https://coder.example.com/extra"
  }

  expect_failures = [var.deployment_origin]
}

run "rejects_non_uuid_workspace" {
  command = plan

  variables {
    workspace_id = "not-a-uuid"
  }

  expect_failures = [var.workspace_id]
}

run "rejects_relative_config_path" {
  command = plan

  variables {
    config_path = "repo/.devcontainer/devcontainer.json"
  }

  expect_failures = [var.config_path]
}

run "rejects_dotdot_workspace_folder" {
  command = plan

  variables {
    workspace_folder = "/home/coder/../etc"
  }

  expect_failures = [var.workspace_folder]
}

run "rejects_uppercase_helper_slug" {
  command = plan

  variables {
    helper_slug = "OrrisDev"
  }

  expect_failures = [var.helper_slug]
}

run "rejects_non_loopback_helper_url" {
  command = plan

  variables {
    helper_loopback_url = "https://helper.example.com:8443"
  }

  expect_failures = [var.helper_loopback_url]
}
