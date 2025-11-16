run "required_vars" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }
}

run "with_custom_version" {
  command = plan

  variables {
    agent_id        = "test-agent-id"
    install_version = "2.15.0"
  }
}

run "with_custom_log_path" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    log_path = "/var/log/aws-cli.log"
  }
}
