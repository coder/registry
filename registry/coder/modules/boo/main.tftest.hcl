run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-defaults"
  }

  assert {
    condition     = length(var.sessions) == 0
    error_message = "sessions should default to []"
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
    condition     = var.icon == "/icon/coder.svg"
    error_message = "icon should default to '/icon/coder.svg'"
  }

  assert {
    condition     = var.order == null
    error_message = "order should default to null"
  }

  assert {
    condition     = var.group == null
    error_message = "group should default to null"
  }

  assert {
    condition     = var.install_script_url == "https://raw.githubusercontent.com/coder/boo/main/install.sh"
    error_message = "install_script_url should default to the upstream GitHub URL"
  }
}

run "test_single_session" {
  command = plan

  variables {
    agent_id = "test-agent-single"
    sessions = [
      {
        session_name = "dev"
        display_name = "Dev Server"
        slug         = "dev"
        command      = "make dev"
      }
    ]
  }

  assert {
    condition     = var.sessions[0].session_name == "dev"
    error_message = "session_name should be 'dev'"
  }

  assert {
    condition     = var.sessions[0].command == "make dev"
    error_message = "command should be 'make dev'"
  }
}

run "test_multiple_sessions" {
  command = plan

  variables {
    agent_id = "test-agent-multi"
    sessions = [
      {
        session_name = "server"
        display_name = "Server"
        slug         = "server"
        command      = "npm run dev"
      },
      {
        session_name = "worker"
        display_name = "Worker"
        slug         = "worker"
        command      = "npm run worker"
      },
      {
        session_name = "shell"
        display_name = "Shell"
        slug         = "shell"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = length(var.sessions) == 3
    error_message = "sessions should contain 3 entries"
  }

  assert {
    condition     = var.sessions[0].command == "npm run dev"
    error_message = "first session command should be 'npm run dev'"
  }
}

run "test_skip_install" {
  command = plan

  variables {
    agent_id = "test-agent-skip"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
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
    agent_id = "test-agent-pinned"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
    boo_version = "v0.6.4"
  }

  assert {
    condition     = var.boo_version == "v0.6.4"
    error_message = "boo_version should be 'v0.6.4'"
  }
}

run "test_icon_order_group" {
  command = plan

  variables {
    agent_id = "test-agent-app"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "boo-main"
        command      = "bash"
      }
    ]
    icon  = "/icon/custom.svg"
    order = 10
    group = "terminals"
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
    agent_id = "test-agent-hooks"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
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
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
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
    sessions = [
      {
        session_name = "alpha"
        display_name = "Alpha"
        slug         = "alpha"
        command      = "bash"
      },
      {
        session_name = "beta"
        display_name = "Beta"
        slug         = "beta"
        command      = "bash"
      }
    ]
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
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = output.scripts == ["coder-boo-pre_install_script", "coder-boo-install_script", "coder-boo-post_install_script"]
    error_message = "scripts output should list pre_install, install, and post_install scripts in run order"
  }
}

run "test_custom_install_script_url" {
  command = plan

  variables {
    agent_id           = "test-agent-url"
    install_script_url = "https://mirror.example.com/boo/install.sh"
    sessions = [
      {
        session_name = "main"
        display_name = "Main"
        slug         = "main"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = var.install_script_url == "https://mirror.example.com/boo/install.sh"
    error_message = "install_script_url should be overridable"
  }
}

run "test_session_name_in_command" {
  command = plan

  variables {
    agent_id = "test-agent-cmd"
    sessions = [
      {
        session_name = "my-session"
        display_name = "My Session"
        slug         = "my-boo"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = can(regex("'my-session'", coder_app.boo["my-boo"].command))
    error_message = "boo command should use session_name 'my-session', not slug 'my-boo'"
  }
}

run "test_derived_slug" {
  command = plan

  variables {
    agent_id = "test-agent-derived-slug"
    sessions = [
      {
        session_name = "my.dev_server"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = coder_app.boo["my-dev-server"].slug == "my-dev-server"
    error_message = "slug should be derived as 'my-dev-server' from session_name 'my.dev_server'"
  }
}

run "test_derived_display_name" {
  command = plan

  variables {
    agent_id = "test-agent-derived-dn"
    sessions = [
      {
        session_name = "my-session"
        command      = "bash"
      }
    ]
  }

  assert {
    condition     = coder_app.boo["my-session"].display_name == "my-session"
    error_message = "display_name should default to session_name 'my-session' when omitted"
  }
}

run "test_install_only" {
  command = plan

  variables {
    agent_id = "test-agent-install-only"
  }

  assert {
    condition     = length(var.sessions) == 0
    error_message = "sessions should default to []"
  }

  assert {
    condition     = length(coder_app.boo) == 0
    error_message = "no coder_app resources should be created with no sessions"
  }
}
