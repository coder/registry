run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-defaults"
  }

  assert {
    condition     = var.sessions == {}
    error_message = "sessions should default to {}"
  }

  assert {
    condition     = var.install_boo == true
    error_message = "install_boo should default to true"
  }

  assert {
    condition     = var.boo_version == "latest"
    error_message = "boo_version should default to 'latest'"
  }

  assert {
    condition     = var.display_name == "Boo"
    error_message = "display_name should default to 'Boo'"
  }

  assert {
    condition     = var.slug == "boo"
    error_message = "slug should default to 'boo'"
  }

  assert {
    condition     = var.icon == "/icon/boo.svg"
    error_message = "icon should default to '/icon/boo.svg'"
  }

  assert {
    condition     = var.order == null
    error_message = "order should default to null"
  }

  assert {
    condition     = var.group == null
    error_message = "group should default to null"
  }
}

run "test_single_session" {
  command = plan

  variables {
    agent_id = "test-agent-single"
    sessions = { dev = "make dev" }
  }

  assert {
    condition     = var.sessions["dev"] == "make dev"
    error_message = "sessions map should contain the correct command for key 'dev'"
  }
}

run "test_multiple_sessions" {
  command = plan

  variables {
    agent_id = "test-agent-multi"
    sessions = {
      server = "npm run dev"
      worker = "npm run worker"
      shell  = "bash"
    }
  }

  assert {
    condition     = length(var.sessions) == 3
    error_message = "sessions should contain 3 entries"
  }

  assert {
    condition     = var.sessions["server"] == "npm run dev"
    error_message = "sessions['server'] should be 'npm run dev'"
  }

  assert {
    condition     = var.sessions["worker"] == "npm run worker"
    error_message = "sessions['worker'] should be 'npm run worker'"
  }
}

run "test_skip_install" {
  command = plan

  variables {
    agent_id    = "test-agent-skip"
    sessions    = { main = "bash" }
    install_boo = false
  }

  assert {
    condition     = var.install_boo == false
    error_message = "install_boo should be false"
  }
}

run "test_pinned_version" {
  command = plan

  variables {
    agent_id    = "test-agent-pinned"
    sessions    = { main = "bash" }
    boo_version = "v0.6.4"
  }

  assert {
    condition     = var.boo_version == "v0.6.4"
    error_message = "boo_version should be 'v0.6.4'"
  }
}

run "test_custom_app" {
  command = plan

  variables {
    agent_id     = "test-agent-app"
    sessions     = { main = "bash" }
    slug         = "my-boo"
    display_name = "My Boo"
    icon         = "/icon/custom.svg"
    order        = 10
    group        = "terminals"
  }

  assert {
    condition     = var.slug == "my-boo"
    error_message = "slug should be 'my-boo'"
  }

  assert {
    condition     = var.display_name == "My Boo"
    error_message = "display_name should be 'My Boo'"
  }

  assert {
    condition     = var.icon == "/icon/custom.svg"
    error_message = "icon should be '/icon/custom.svg'"
  }

  assert {
    condition     = var.order == 10
    error_message = "order should be 10"
  }

  assert {
    condition     = var.group == "terminals"
    error_message = "group should be 'terminals'"
  }
}

run "test_hooks" {
  command = plan

  variables {
    agent_id            = "test-agent-hooks"
    sessions            = { main = "bash" }
    pre_install_script  = "echo 'pre-install'"
    post_install_script = "echo 'post-install'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'pre-install'"
    error_message = "pre_install_script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'post-install'"
    error_message = "post_install_script should be set correctly"
  }
}

run "test_scripts_output_single_session" {
  command = plan

  variables {
    agent_id = "test-agent-output-single"
    sessions = { main = "bash" }
  }

  assert {
    condition     = output.scripts == ["coder-boo-install_script"]
    error_message = "scripts output should list install_script"
  }
}

run "test_scripts_output_multi_session" {
  command = plan

  variables {
    agent_id = "test-agent-output-multi"
    sessions = {
      alpha = "bash"
      beta  = "bash"
    }
  }

  assert {
    condition     = output.scripts == ["coder-boo-install_script"]
    error_message = "scripts output should list install_script"
  }
}

run "test_scripts_output_with_hooks" {
  command = plan

  variables {
    agent_id            = "test-agent-output-hooks"
    sessions            = { main = "bash" }
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-boo-pre_install_script", "coder-boo-install_script", "coder-boo-post_install_script"]
    error_message = "scripts output should list pre_install, install, and post_install scripts in run order"
  }
}

run "test_slug_normalization" {
  command = plan

  variables {
    agent_id = "test-agent-slug-norm"
    sessions = {
      "Claude Code" = "claude"
      "Codex"       = "codex"
      my_session    = "bash"
    }
  }

  assert {
    condition     = local.session_slugs["Claude Code"] == "claude-code"
    error_message = "'Claude Code' should normalize to 'claude-code'"
  }

  assert {
    condition     = local.session_slugs["Codex"] == "codex"
    error_message = "'Codex' should normalize to 'codex'"
  }

  assert {
    condition     = local.session_slugs["my_session"] == "my-session"
    error_message = "'my_session' should normalize to 'my-session'"
  }
}

run "test_install_only" {
  command = plan

  variables {
    agent_id = "test-agent-install-only"
  }

  assert {
    condition     = var.sessions == {}
    error_message = "sessions should default to {}"
  }

  assert {
    condition     = length(coder_app.boo) == 0
    error_message = "no coder_app resources should be created with no sessions"
  }
}
