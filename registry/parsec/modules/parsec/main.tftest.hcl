run "basic_validation" {
  command = plan

  assert {
    condition     = coder_script.parsec_install.run_on_start == true
    error_message = "Parsec install script should run on start"
  }

  assert {
    condition     = coder_app.parsec.display_name == "Parsec"
    error_message = "Parsec app display name should be 'Parsec'"
  }

  assert {
    condition     = coder_app.parsec.slug == "parsec"
    error_message = "Parsec app slug should be 'parsec'"
  }

  assert {
    condition     = coder_app.parsec.icon == "/icon/parsec.svg"
    error_message = "Parsec app icon should be '/icon/parsec.svg'"
  }
}

run "custom_port" {
  command = plan

  variables {
    port = 9000
  }

  assert {
    condition     = coder_app.parsec.url == "http://localhost:9000"
    error_message = "Parsec URL should use custom port 9000"
  }
}

run "custom_order_and_group" {
  command = plan

  variables {
    order = 5
    group = "Remote Desktop"
  }

  assert {
    condition     = coder_app.parsec.order == 5
    error_message = "Parsec app order should be 5"
  }

  assert {
    condition     = coder_app.parsec.group == "Remote Desktop"
    error_message = "Parsec app group should be 'Remote Desktop'"
  }
}
