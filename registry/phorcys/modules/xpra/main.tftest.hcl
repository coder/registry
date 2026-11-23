variables {
  agent_id = "example-agent-id"
  command  = "gimp"
  slug     = "gimp"
}

run "defaults" {
  command = plan

  assert {
    condition     = coder_app.xpra.url == "http://localhost:14500/?floating_menu=false"
    error_message = "app URL must use the default port and hide the floating menu"
  }

  assert {
    condition     = coder_app.xpra.subdomain == true
    error_message = "app must use subdomain routing"
  }

  assert {
    condition     = coder_app.xpra.open_in == "slim-window"
    error_message = "app must open in a slim window by default"
  }

  assert {
    condition     = one([for h in coder_app.xpra.healthcheck : h.url]) == "http://localhost:14500/"
    error_message = "healthcheck must target the xpra port"
  }

  assert {
    condition     = local.module_dir == "$HOME/.coder-modules/phorcys/xpra-gimp"
    error_message = "module directory must include the slug"
  }
}

run "custom_port" {
  command = plan

  variables {
    port = 14600
  }

  assert {
    condition     = coder_app.xpra.url == "http://localhost:14600/?floating_menu=false"
    error_message = "app URL must use the configured port"
  }

  assert {
    condition     = strcontains(local.start_script, "ARG_PORT='14600'")
    error_message = "start script must use the configured port"
  }
}

run "start_script" {
  command = plan

  variables {
    command    = "java -jar 'my app.jar'"
    env        = { GDK_SCALE = "2" }
    extra_args = ["--min-quality=80"]
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("java -jar 'my app.jar'"))
    error_message = "start script must contain the base64 command"
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("GDK_SCALE=${base64encode("2")}"))
    error_message = "start script must contain the encoded env"
  }

  assert {
    condition     = strcontains(local.start_script, base64encode(base64encode("--min-quality=80")))
    error_message = "start script must contain the encoded extra args"
  }

  assert {
    condition     = strcontains(local.start_script, "--resize-display=yes")
    error_message = "start script must resize the display to the browser"
  }
}

run "install_toggles" {
  command = plan

  variables {
    install_xpra    = false
    install_openbox = false
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_INSTALL_XPRA='false'")
    error_message = "install script must honor install_xpra"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_INSTALL_OPENBOX='false'")
    error_message = "install script must honor install_openbox"
  }
}

run "invalid_slug" {
  command = plan

  variables {
    slug = "Bad_Slug"
  }

  expect_failures = [var.slug]
}

run "invalid_port" {
  command = plan

  variables {
    port = 80
  }

  expect_failures = [var.port]
}

run "invalid_env_key" {
  command = plan

  variables {
    env = { "1BAD" = "x" }
  }

  expect_failures = [var.env]
}
