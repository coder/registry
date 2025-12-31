# Test for jfrog-oauth module

run "test_required_vars" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    jfrog_url        = "https://example.jfrog.io"
    package_managers = {}
  }

  # Mock external auth with valid access token for basic test
  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }
}

run "test_empty_access_token_fails" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    jfrog_url        = "https://example.jfrog.io"
    package_managers = {}
  }

  # Mock external auth with empty access token
  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = ""
    }
  }

  expect_failures = [
    resource.coder_script.jfrog
  ]
}

run "test_valid_access_token_succeeds" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    jfrog_url        = "https://example.jfrog.io"
    package_managers = {}
  }

  # Mock external auth with valid access token
  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # Verify the script resource is created
  assert {
    condition     = resource.coder_script.jfrog.agent_id == "test-agent-id"
    error_message = "coder_script agent_id should match the input variable"
  }

  assert {
    condition     = resource.coder_script.jfrog.display_name == "jfrog"
    error_message = "coder_script display_name should be 'jfrog'"
  }
}

run "test_jfrog_url_validation" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    jfrog_url        = "invalid-url"
    package_managers = {}
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  expect_failures = [
    var.jfrog_url
  ]
}

run "test_username_field_validation" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    jfrog_url        = "https://example.jfrog.io"
    username_field   = "invalid"
    package_managers = {}
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  expect_failures = [
    var.username_field
  ]
}

run "test_with_npm_package_manager" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      npm = ["global", "@foo:foo", "@bar:bar"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  assert {
    condition     = resource.coder_script.jfrog.run_on_start == true
    error_message = "coder_script should run on start"
  }

  # Verify npm configuration is in script
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "jf npmc --global --repo-resolve \"global\"")
    error_message = "script should contain jf npmc command for npm"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "@foo:registry=https://example.jfrog.io/artifactory/api/npm/foo")
    error_message = "script should contain scoped npm registry for @foo"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "@bar:registry=https://example.jfrog.io/artifactory/api/npm/bar")
    error_message = "script should contain scoped npm registry for @bar"
  }
}

run "test_configure_code_server" {
  command = plan

  variables {
    agent_id              = "test-agent-id"
    jfrog_url             = "https://example.jfrog.io"
    configure_code_server = true
    package_managers      = {}
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # When configure_code_server is true, env vars should be created
  assert {
    condition     = length(resource.coder_env.jfrog_ide_url) == 1
    error_message = "coder_env.jfrog_ide_url should be created when configure_code_server is true"
  }

  assert {
    condition     = length(resource.coder_env.jfrog_ide_access_token) == 1
    error_message = "coder_env.jfrog_ide_access_token should be created when configure_code_server is true"
  }
}

run "test_go_proxy_env" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      go = ["foo", "bar", "baz"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # When go package manager is configured, GOPROXY env should be set
  assert {
    condition     = length(resource.coder_env.goproxy) == 1
    error_message = "coder_env.goproxy should be created when go package manager is configured"
  }

  # Verify GOPROXY contains all repos
  assert {
    condition     = strcontains(resource.coder_env.goproxy[0].value, "example.jfrog.io/artifactory/api/go/foo")
    error_message = "GOPROXY should contain foo repo"
  }

  assert {
    condition     = strcontains(resource.coder_env.goproxy[0].value, "example.jfrog.io/artifactory/api/go/bar")
    error_message = "GOPROXY should contain bar repo"
  }

  assert {
    condition     = strcontains(resource.coder_env.goproxy[0].value, "example.jfrog.io/artifactory/api/go/baz")
    error_message = "GOPROXY should contain baz repo"
  }

  # Verify script contains go configuration
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "jf goc --global --repo-resolve \"foo\"")
    error_message = "script should contain jf goc command"
  }
}

run "test_pypi_package_manager" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      pypi = ["global", "foo", "bar"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # Verify pip configuration in script
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "jf pipc --global --repo-resolve \"global\"")
    error_message = "script should contain jf pipc command"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "index-url = https://default:valid-token-value@example.jfrog.io/artifactory/api/pypi/global/simple")
    error_message = "script should contain pip index-url configuration"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "extra-index-url")
    error_message = "script should contain extra-index-url for additional repos"
  }
}

run "test_docker_package_manager" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      docker = ["foo.jfrog.io", "bar.jfrog.io", "baz.jfrog.io"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # Verify docker registration commands in script
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "register_docker \"foo.jfrog.io\"")
    error_message = "script should contain register_docker for foo.jfrog.io"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "register_docker \"bar.jfrog.io\"")
    error_message = "script should contain register_docker for bar.jfrog.io"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "register_docker \"baz.jfrog.io\"")
    error_message = "script should contain register_docker for baz.jfrog.io"
  }
}

run "test_conda_package_manager" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      conda = ["conda-main", "conda-secondary", "conda-local"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # Verify conda configuration in script
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "channels:")
    error_message = "script should contain conda channels configuration"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "example.jfrog.io/artifactory/api/conda/conda-main")
    error_message = "script should contain conda-main channel"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "example.jfrog.io/artifactory/api/conda/conda-secondary")
    error_message = "script should contain conda-secondary channel"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "example.jfrog.io/artifactory/api/conda/conda-local")
    error_message = "script should contain conda-local channel"
  }
}

run "test_maven_package_manager" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    jfrog_url = "https://example.jfrog.io"
    package_managers = {
      maven = ["central", "snapshots", "local"]
    }
  }

  override_data {
    target = data.coder_external_auth.jfrog
    values = {
      access_token = "valid-token-value"
    }
  }

  # Verify maven jf mvnc command
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "jf mvnc --global")
    error_message = "script should contain jf mvnc command"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "--repo-resolve-releases \"central\"")
    error_message = "script should contain repo-resolve-releases for central"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "--repo-resolve-snapshots \"central\"")
    error_message = "script should contain repo-resolve-snapshots for central"
  }

  # Verify settings.xml content
  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "<servers>")
    error_message = "script should contain maven servers configuration"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "<id>central</id>")
    error_message = "script should contain central server id"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "<id>snapshots</id>")
    error_message = "script should contain snapshots server id"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "<id>local</id>")
    error_message = "script should contain local server id"
  }

  assert {
    condition     = strcontains(resource.coder_script.jfrog.script, "<url>https://example.jfrog.io/artifactory/central</url>")
    error_message = "script should contain central repository URL"
  }
}
