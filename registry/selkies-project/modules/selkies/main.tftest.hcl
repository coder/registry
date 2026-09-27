mock_provider "coder" {}

run "defaults" {
  command = plan

  variables {
    agent_id = "agent"
  }

  assert {
    condition     = coder_app.selkies.url == "http://localhost:8080"
    error_message = "The app must reach Selkies on the default port."
  }

  assert {
    condition     = coder_app.selkies.slug == "selkies" && coder_app.selkies.display_name == "Selkies" && coder_app.selkies.icon == "/icon/selkies.svg"
    error_message = "The app must be named and branded Selkies."
  }

  assert {
    condition     = coder_app.selkies.subdomain && coder_app.selkies.share == "owner"
    error_message = "The app must default to a subdomain its owner alone opens, as the KasmVNC module's does."
  }

  assert {
    condition     = local.module_directory == "$HOME/.coder-modules/selkies-project/selkies"
    error_message = "The module must keep its data under the standard per-module root."
  }

  assert {
    condition     = strcontains(local.start_script, "--enable-basic-auth=false --enable-https=false") && !strcontains(local.start_script, "--public")
    error_message = "Selkies must listen on the loopback addresses alone, leaving the login and TLS to Coder."
  }

  assert {
    condition     = strcontains(local.start_script, "ARG_DESKTOP=$(echo -n '' | base64 -d)")
    error_message = "An empty desktop_environment must start the workspace's default desktop."
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_INSTALL='true'") && strcontains(local.install_script, "ARG_VERSION=''")
    error_message = "The module must install the latest release where the workspace lacks Selkies."
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_RELEASE_URL='https://github.com/selkies-project/selkies/releases'") && !strcontains(local.install_script, "api.github.com")
    error_message = "The latest release must be resolved from GitHub's releases redirect, not its rate-limited API."
  }
}

run "health_check_and_scripts" {
  command = apply

  variables {
    agent_id = "agent"
  }

  assert {
    condition     = one(coder_app.selkies.healthcheck).url == "http://localhost:8080/api/health"
    error_message = "The health check must use Selkies' /api/health endpoint."
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "The module must run an install script and then a start script."
  }
}

run "kasmvnc_module_variables" {
  command = plan

  variables {
    agent_id            = "agent"
    desktop_environment = "xfce"
    port                = 6800
    subdomain           = false
    share               = "authenticated"
    order               = 3
    group               = "Desktops"
  }

  assert {
    condition     = coder_app.selkies.url == "http://localhost:6800" && !coder_app.selkies.subdomain && coder_app.selkies.share == "authenticated"
    error_message = "The app must follow the port, subdomain, and share variables."
  }

  assert {
    condition     = coder_app.selkies.order == 3 && coder_app.selkies.group == "Desktops"
    error_message = "The app must keep its order and group."
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("xfce")) && strcontains(local.start_script, "ARG_PORT='6800'")
    error_message = "The start script must start the named desktop on the configured port."
  }
}

run "desktop_command" {
  command = plan

  variables {
    agent_id            = "agent"
    desktop_environment = "startxfce4 --replace 'now'"
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("startxfce4 --replace 'now'"))
    error_message = "A desktop command must reach the start script intact, quotes included."
  }
}

run "wayland" {
  command = plan

  variables {
    agent_id = "agent"
    wayland  = true
  }

  assert {
    condition     = strcontains(local.start_script, "ARG_WAYLAND='true'") && strcontains(local.install_script, "ARG_WAYLAND='true'")
    error_message = "The Wayland backend must reach both scripts, so neither starts nor installs an Xvfb."
  }
}

run "image_carries_selkies" {
  command = plan

  variables {
    agent_id        = "agent"
    install_selkies = false
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_INSTALL='false'")
    error_message = "install_selkies = false must keep the install script from installing."
  }
}

run "pinned_release_from_a_mirror" {
  command = plan

  variables {
    agent_id        = "agent"
    selkies_version = "2.0.0"
    release_url     = "https://artifacts.example.com/selkies/releases"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_VERSION='2.0.0'") && strcontains(local.install_script, "ARG_RELEASE_URL='https://artifacts.example.com/selkies/releases'")
    error_message = "The install script must download the pinned release from the mirror."
  }
}

run "rejects_an_invalid_share" {
  command = plan

  variables {
    agent_id = "agent"
    share    = "everyone"
  }

  expect_failures = [var.share]
}

run "rejects_a_version_that_is_not_a_tag" {
  command = plan

  variables {
    agent_id        = "agent"
    selkies_version = "2.0.0'; true"
  }

  expect_failures = [var.selkies_version]
}

run "rejects_a_release_url_with_a_trailing_slash" {
  command = plan

  variables {
    agent_id    = "agent"
    release_url = "https://github.com/selkies-project/selkies/releases/"
  }

  expect_failures = [var.release_url]
}

run "rejects_a_port_out_of_range" {
  command = plan

  variables {
    agent_id = "agent"
    port     = 70000
  }

  expect_failures = [var.port]
}
