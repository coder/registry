run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }
}

run "plan_with_oauth" {
  command = plan

  variables {
    agent_id            = "example-agent-id"
    oauth_client_id     = "tskey-client-xxxx"
    oauth_client_secret = "tskey-secret-xxxx"
  }
}

run "plan_with_auth_key" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    auth_key = "tskey-auth-xxxx"
  }
}

run "plan_userspace_mode" {
  command = plan

  variables {
    agent_id        = "example-agent-id"
    auth_key        = "tskey-auth-xxxx"
    networking_mode = "userspace"
  }
}

run "plan_with_extra_flags" {
  command = plan

  variables {
    agent_id    = "example-agent-id"
    auth_key    = "tskey-auth-xxxx"
    extra_flags = "--shields-up"
  }
}
