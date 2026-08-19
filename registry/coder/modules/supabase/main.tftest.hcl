run "test_supabase_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.install_method == "auto"
    error_message = "Install method should default to 'auto'"
  }

  assert {
    condition     = var.supabase_version == "latest"
    error_message = "Version should default to 'latest'"
  }

  assert {
    condition     = var.use_external_auth == true
    error_message = "use_external_auth should default to true"
  }
}

run "test_supabase_with_direct_token" {
  command = plan

  variables {
    agent_id          = "test-agent-456"
    use_external_auth = false
    access_token      = "sbp_test_token_1234567890abcdef12345678"
  }

  assert {
    condition     = var.use_external_auth == false
    error_message = "use_external_auth should be false"
  }

  assert {
    condition     = var.access_token == "sbp_test_token_1234567890abcdef12345678"
    error_message = "Access token should be set correctly"
  }
}

run "test_supabase_with_custom_install_method" {
  command = plan

  variables {
    agent_id       = "test-agent-789"
    install_method = "binary"
  }

  assert {
    condition     = var.install_method == "binary"
    error_message = "Install method should be 'binary'"
  }
}

run "test_supabase_with_brew_install" {
  command = plan

  variables {
    agent_id       = "test-agent-brew"
    install_method = "brew"
  }

  assert {
    condition     = var.install_method == "brew"
    error_message = "Install method should be 'brew'"
  }
}

run "test_supabase_with_scoop_install" {
  command = plan

  variables {
    agent_id       = "test-agent-scoop"
    install_method = "scoop"
  }

  assert {
    condition     = var.install_method == "scoop"
    error_message = "Install method should be 'scoop'"
  }
}

run "test_supabase_with_specific_version" {
  command = plan

  variables {
    agent_id         = "test-agent-version"
    supabase_version = "2.0.0"
  }

  assert {
    condition     = var.supabase_version == "2.0.0"
    error_message = "Version should be '2.0.0'"
  }
}

run "test_supabase_with_db_password" {
  command = plan

  variables {
    agent_id          = "test-agent-db"
    use_external_auth = false
    access_token      = "sbp_test_token"
    db_password       = "my-secret-password"
  }

  assert {
    condition     = var.db_password == "my-secret-password"
    error_message = "Database password should be set correctly"
  }
}

run "test_supabase_with_custom_external_auth_id" {
  command = plan

  variables {
    agent_id         = "test-agent-auth"
    external_auth_id = "my-supabase-oauth"
  }

  assert {
    condition     = var.external_auth_id == "my-supabase-oauth"
    error_message = "External auth ID should be 'my-supabase-oauth'"
  }
}

run "test_supabase_with_custom_icon" {
  command = plan

  variables {
    agent_id = "test-agent-icon"
    icon     = "/icon/custom-supabase.svg"
  }

  assert {
    condition     = var.icon == "/icon/custom-supabase.svg"
    error_message = "Icon should be set to custom path"
  }
}

run "test_supabase_with_pre_install_script" {
  command = plan

  variables {
    agent_id           = "test-agent-pre"
    pre_install_script = "echo 'Pre-install script'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install script'"
    error_message = "Pre-install script should be set"
  }
}

run "test_supabase_with_post_install_script" {
  command = plan

  variables {
    agent_id            = "test-agent-post"
    post_install_script = "echo 'Post-install script'"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install script'"
    error_message = "Post-install script should be set"
  }
}
