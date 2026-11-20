mock_provider "coder" {}

run "defaults" {
  command = apply

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = output.docker_host == "unix:///tmp/podman.sock"
    error_message = "Expected DOCKER_HOST to point at the default socket."
  }

  assert {
    condition     = coder_env.docker_host[0].value == "unix:///tmp/podman.sock"
    error_message = "Expected DOCKER_HOST env var."
  }

  assert {
    condition     = coder_env.docker_buildkit[0].value == "0"
    error_message = "Expected DOCKER_BUILDKIT=0 by default."
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "Expected install + start scripts."
  }
}

run "no_socket" {
  command = apply

  variables {
    agent_id = "example-agent-id"
    socket   = false
  }

  assert {
    condition     = length(coder_env.docker_host) == 0 && output.docker_host == ""
    error_message = "Expected no DOCKER_HOST when socket = false."
  }

  assert {
    condition     = length(output.scripts) == 1
    error_message = "Expected only the install script when socket = false."
  }
}

run "keep_buildkit" {
  command = apply

  variables {
    agent_id         = "example-agent-id"
    disable_buildkit = false
  }

  assert {
    condition     = length(coder_env.docker_buildkit) == 0
    error_message = "Expected no DOCKER_BUILDKIT when disable_buildkit = false."
  }
}

run "custom_socket" {
  command = apply

  variables {
    agent_id    = "example-agent-id"
    socket_path = "/run/user/1000/podman/podman.sock"
  }

  assert {
    condition     = output.docker_host == "unix:///run/user/1000/podman/podman.sock"
    error_message = "Expected DOCKER_HOST to follow socket_path."
  }
}

run "relative_socket_rejected" {
  command = plan

  variables {
    agent_id    = "example-agent-id"
    socket_path = "podman.sock"
  }

  expect_failures = [var.socket_path]
}

run "required_tools_accepts_commands" {
  command = plan

  variables {
    agent_id       = "example-agent-id"
    required_tools = ["buildah", "skopeo"]
  }
}

run "required_tools_rejects_shell_syntax" {
  command = plan

  variables {
    agent_id       = "example-agent-id"
    required_tools = ["buildah; rm -rf /"]
  }

  expect_failures = [var.required_tools]
}
