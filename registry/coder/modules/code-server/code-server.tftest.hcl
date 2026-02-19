run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "offline_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
    offline    = true
  }

  expect_failures = [
    resource.coder_script.code-server
  ]
}

run "offline_disallows_extensions" {
  command = plan

  variables {
    agent_id   = "foo"
    offline    = true
    extensions = ["ms-python.python", "golang.go"]
  }

  expect_failures = [
    resource.coder_script.code-server
  ]
}

run "url_with_folder_query" {
  command = plan

  variables {
    agent_id = "foo"
    folder   = "/home/coder/project"
    port     = 13337
  }

  assert {
    condition     = resource.coder_app.code-server.url == "http://localhost:13337/?folder=%2Fhome%2Fcoder%2Fproject"
    error_message = "coder_app URL must include encoded folder query param"
  }
}

run "trusted_domains_single" {
  command = plan

  variables {
    agent_id        = "foo"
    trusted_domains = ["example.com"]
  }

  assert {
    condition     = can(regex("example.com", resource.coder_script.code-server.script))
    error_message = "Script must contain the trusted domain 'example.com'"
  }
}

run "trusted_domains_multiple" {
  command = plan

  variables {
    agent_id        = "foo"
    trusted_domains = ["example.com", "test.com", "trusted.domain.com"]
  }

  assert {
    condition     = can(regex("example.com,test.com,trusted.domain.com", resource.coder_script.code-server.script))
    error_message = "Script must contain the comma-separated trusted domains 'example.com,test.com,trusted.domain.com'"
  }
}

run "trusted_domains_empty" {
  command = plan

  variables {
    agent_id        = "foo"
    trusted_domains = []
  }

  assert {
    condition     = can(regex("TRUSTED_DOMAINS_ARG=\"\"", resource.coder_script.code-server.script))
    error_message = "Script must set TRUSTED_DOMAINS_ARG to empty string when no domains are provided"
  }
}
