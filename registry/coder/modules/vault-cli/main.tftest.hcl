mock_provider "coder" {}

variables {
  agent_id   = "test-agent-id"
  vault_addr = "https://vault.example.com"
}

run "test_vault_cli_without_token" {
  assert {
    condition     = resource.coder_script.vault_cli.display_name == "Vault CLI"
    error_message = "Display name should be 'Vault CLI'"
  }

  assert {
    condition     = resource.coder_env.vault_addr.name == "VAULT_ADDR"
    error_message = "VAULT_ADDR environment variable should be set"
  }

  assert {
    condition     = resource.coder_env.vault_addr.value == "https://vault.example.com"
    error_message = "VAULT_ADDR should match the provided vault_addr"
  }

  assert {
    condition     = length(resource.coder_env.vault_token) == 0
    error_message = "VAULT_TOKEN should not be set when vault_token is not provided"
  }

  assert {
    condition     = length(resource.coder_env.vault_namespace) == 0
    error_message = "VAULT_NAMESPACE should not be set when vault_namespace is not provided"
  }
}

run "test_vault_cli_with_token" {
  variables {
    vault_token = "test-vault-token"
  }

  assert {
    condition     = resource.coder_script.vault_cli.display_name == "Vault CLI"
    error_message = "Display name should be 'Vault CLI'"
  }

  assert {
    condition     = resource.coder_env.vault_addr.name == "VAULT_ADDR"
    error_message = "VAULT_ADDR environment variable should be set"
  }

  assert {
    condition     = length(resource.coder_env.vault_token) == 1
    error_message = "VAULT_TOKEN should be set when vault_token is provided"
  }

  assert {
    condition     = resource.coder_env.vault_token[0].name == "VAULT_TOKEN"
    error_message = "VAULT_TOKEN environment variable name should be correct"
  }

  assert {
    condition     = resource.coder_env.vault_token[0].value == "test-vault-token"
    error_message = "VAULT_TOKEN should match the provided vault_token"
  }
}

run "test_vault_cli_custom_version" {
  variables {
    vault_cli_version = "1.15.0"
  }

  assert {
    condition     = output.vault_cli_version == "1.15.0"
    error_message = "Vault CLI version output should match the provided version"
  }
}

run "test_vault_cli_custom_install_dir" {
  variables {
    install_dir = "/custom/install/dir"
  }

  assert {
    condition     = resource.coder_script.vault_cli.display_name == "Vault CLI"
    error_message = "Display name should be 'Vault CLI'"
  }
}

run "test_vault_cli_invalid_version" {
  command = plan

  variables {
    vault_cli_version = "invalid-version"
  }

  expect_failures = [var.vault_cli_version]
}

run "test_vault_cli_valid_semver" {
  variables {
    vault_cli_version = "1.18.3"
  }

  assert {
    condition     = output.vault_cli_version == "1.18.3"
    error_message = "Vault CLI version output should match the provided version"
  }
}

run "test_vault_cli_rejects_v_prefix" {
  command = plan

  variables {
    vault_cli_version = "v1.18.3"
  }

  expect_failures = [var.vault_cli_version]
}

run "test_vault_cli_with_namespace" {
  variables {
    vault_namespace = "admin/my-namespace"
  }

  assert {
    condition     = length(resource.coder_env.vault_namespace) == 1
    error_message = "VAULT_NAMESPACE should be set when vault_namespace is provided"
  }

  assert {
    condition     = resource.coder_env.vault_namespace[0].name == "VAULT_NAMESPACE"
    error_message = "VAULT_NAMESPACE environment variable name should be correct"
  }

  assert {
    condition     = resource.coder_env.vault_namespace[0].value == "admin/my-namespace"
    error_message = "VAULT_NAMESPACE should match the provided vault_namespace"
  }
}

run "test_vault_cli_with_token_and_namespace" {
  variables {
    vault_token     = "test-vault-token"
    vault_namespace = "admin/my-namespace"
  }

  assert {
    condition     = length(resource.coder_env.vault_token) == 1
    error_message = "VAULT_TOKEN should be set when vault_token is provided"
  }

  assert {
    condition     = length(resource.coder_env.vault_namespace) == 1
    error_message = "VAULT_NAMESPACE should be set when vault_namespace is provided"
  }

  assert {
    condition     = resource.coder_env.vault_token[0].value == "test-vault-token"
    error_message = "VAULT_TOKEN should match the provided vault_token"
  }

  assert {
    condition     = resource.coder_env.vault_namespace[0].value == "admin/my-namespace"
    error_message = "VAULT_NAMESPACE should match the provided vault_namespace"
  }
}

run "test_vault_cli_enterprise" {
  variables {
    enterprise = true
  }

  assert {
    condition     = resource.coder_script.vault_cli.display_name == "Vault CLI"
    error_message = "Display name should be 'Vault CLI'"
  }
}
