mock_provider "coder" {}

variables {
  agent_id            = "test-agent-id"
  broker_endpoint     = "https://broker.example.com"
  broker_capabilities = ["github.repo.read"]
}

run "defaults" {
  command = plan

  assert {
    condition     = output.pade_version == "v0.3.0"
    error_message = "pade_version should default to v0.3.0"
  }

  assert {
    condition     = output.bindings_path == "~/.config/pade/coder-bindings.yaml"
    error_message = "bindings_path output should be stable"
  }

  assert {
    condition     = local.broker_audience == "https://broker.example.com"
    error_message = "broker_audience should default to broker_endpoint"
  }

  assert {
    condition = yamldecode(local.bindings) == {
      version = "0.1"
      capabilities = {
        "github.repo.read" = {
          provider = "broker"
          broker = {
            endpoint = "https://broker.example.com"
            audience = "https://broker.example.com"
            identity = "gce"
          }
        }
      }
    }
    error_message = "bindings should contain only the requested capability with default broker coordinates"
  }

  assert {
    condition     = output.scripts == ["after-certainty-pade-install_script"]
    error_message = "only the install synchronization name should be exposed"
  }

  assert {
    condition     = strcontains(local.install_script, "PADE_VERSION='v0.3.0'")
    error_message = "installer should be rendered with the normalized PADE version"
  }

  assert {
    condition     = strcontains(local.install_script, "BINDINGS_B64='${base64encode(local.bindings)}'")
    error_message = "installer should embed the generated bindings"
  }
}

run "version_normalization" {
  command = plan

  variables {
    pade_version = "0.4.1"
  }

  assert {
    condition     = output.pade_version == "v0.4.1"
    error_message = "pade_version without a leading v should be normalized"
  }

  assert {
    condition     = strcontains(local.install_script, "PADE_VERSION='v0.4.1'")
    error_message = "installer should receive the normalized version"
  }
}

run "version_with_prefix_unchanged" {
  command = plan

  variables {
    pade_version = "v0.4.1"
  }

  assert {
    condition     = output.pade_version == "v0.4.1"
    error_message = "pade_version with a leading v should be preserved"
  }
}

run "invalid_version" {
  command = plan

  variables {
    pade_version = "latest"
  }

  expect_failures = [var.pade_version]
}

run "non_https_endpoint" {
  command = plan

  variables {
    broker_endpoint = "http://broker.example.com"
  }

  expect_failures = [var.broker_endpoint]
}

run "explicit_audience" {
  command = plan

  variables {
    broker_audience = "pade-broker"
  }

  assert {
    condition     = yamldecode(local.bindings).capabilities["github.repo.read"].broker.audience == "pade-broker"
    error_message = "explicit broker_audience should be written to bindings"
  }

  assert {
    condition     = yamldecode(local.bindings).capabilities["github.repo.read"].broker.endpoint == "https://broker.example.com"
    error_message = "explicit audience should not change the endpoint"
  }
}

run "empty_audience" {
  command = plan

  variables {
    broker_audience = "  "
  }

  expect_failures = [var.broker_audience]
}

run "identity_gce" {
  command = plan

  variables {
    broker_identity = "gce"
  }

  assert {
    condition     = yamldecode(local.bindings).capabilities["github.repo.read"].broker.identity == "gce"
    error_message = "gce identity should be written to bindings"
  }
}

run "identity_cursor" {
  command = plan

  variables {
    broker_identity = "cursor"
  }

  assert {
    condition     = yamldecode(local.bindings).capabilities["github.repo.read"].broker.identity == "cursor"
    error_message = "cursor identity should be accepted and written to bindings"
  }
}

run "identity_unsupported" {
  command = plan

  variables {
    broker_identity = "aws"
  }

  expect_failures = [var.broker_identity]
}

run "empty_capabilities" {
  command = plan

  variables {
    broker_capabilities = []
  }

  expect_failures = [var.broker_capabilities]
}

run "blank_capability" {
  command = plan

  variables {
    broker_capabilities = ["github.repo.read", " "]
  }

  expect_failures = [var.broker_capabilities]
}

run "multiple_capabilities" {
  command = plan

  variables {
    broker_endpoint     = "https://other-broker.example.com"
    broker_audience     = "aud"
    broker_identity     = "cursor"
    broker_capabilities = ["github.repo.read", "example.capability"]
  }

  assert {
    condition     = toset(keys(yamldecode(local.bindings).capabilities)) == toset(["example.capability", "github.repo.read"])
    error_message = "bindings should contain exactly the requested capabilities"
  }

  assert {
    condition = alltrue([
      for capability in values(yamldecode(local.bindings).capabilities) :
      capability == {
        provider = "broker"
        broker = {
          endpoint = "https://other-broker.example.com"
          audience = "aud"
          identity = "cursor"
        }
      }
    ])
    error_message = "every binding should use the broker provider with the configured endpoint, audience, and identity"
  }

  assert {
    condition     = toset(keys(yamldecode(local.bindings))) == toset(["capabilities", "version"])
    error_message = "bindings should contain only version and capabilities"
  }
}

run "no_credential_material" {
  command = plan

  assert {
    condition = !can(regex(
      "(?i)(token|secret|password|private key|ghp_|github_pat_|gho_|ghs_)",
      "${local.install_script}\n${local.bindings}",
    ))
    error_message = "installer and bindings must not contain credential material"
  }
}
