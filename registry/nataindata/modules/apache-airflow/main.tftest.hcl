mock_provider "coder" {}

variables {
  agent_id = "test-agent"
}

run "defaults" {
  command = plan

  assert {
    condition     = coder_app.airflow.url == "http://localhost:8080" && coder_app.airflow.share == "owner" && coder_app.airflow.subdomain
    error_message = "Preserve the default Airflow application contract."
  }

  assert {
    condition     = strcontains(local.install_script, "AIRFLOW_VERSION='2.11.0'") && strcontains(local.install_script, "uv tool install") && strcontains(local.install_script, "pipx install")
    error_message = "Render both isolated installers with the default Airflow 2 version."
  }

  assert {
    condition     = var.log_path == "$HOME/.coder-modules/nataindata/apache-airflow/logs/webserver.log"
    error_message = "Default logs must live in the module directory."
  }

  assert {
    condition     = output.scripts == ["nataindata-apache-airflow-install_script", "nataindata-apache-airflow-start_script"]
    error_message = "Expose the ordered coder-utils synchronization names."
  }
}

run "custom_settings" {
  command = plan

  variables {
    port            = 9090
    share           = "authenticated"
    order           = 7
    log_path        = "/home/coder/logs/airflow's output.log"
    airflow_version = "2.10.5"
  }

  assert {
    condition     = coder_app.airflow.url == "http://localhost:9090" && coder_app.airflow.share == "authenticated" && coder_app.airflow.order == 7
    error_message = "Preserve custom application settings."
  }

  assert {
    condition     = strcontains(local.start_script, "--port '9090'") && strcontains(local.start_script, base64encode(var.log_path)) && strcontains(local.install_script, "AIRFLOW_VERSION='2.10.5'")
    error_message = "Render the custom port, safely encoded log path and version."
  }
}

run "reject_airflow_3" {
  command = plan
  variables {
    airflow_version = "3.1.0"
  }
  expect_failures = [var.airflow_version]
}

run "reject_version_injection" {
  command = plan
  variables {
    airflow_version = "2.11.0'; echo injected"
  }
  expect_failures = [var.airflow_version]
}

run "reject_invalid_share" {
  command = plan
  variables {
    share = "everyone"
  }
  expect_failures = [var.share]
}

run "reject_legacy_cli" {
  command = plan
  variables {
    airflow_version = "2.6.3"
  }
  expect_failures = [var.airflow_version]
}

run "reject_invalid_port" {
  command = plan
  variables {
    port = 65536
  }
  expect_failures = [var.port]
}

run "reject_fractional_port" {
  command = plan
  variables {
    port = 8080.5
  }
  expect_failures = [var.port]
}
