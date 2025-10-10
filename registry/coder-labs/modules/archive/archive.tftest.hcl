mock_provider "coder" {}

run "apply_defaults" {
  command = apply

  variables {
    agent_id = "agent-123"
    paths    = ["~/project", "/etc/hosts"]
  }

  assert {
    condition     = output.archive_path == "/tmp/coder-archive.tar.gz"
    error_message = "archive_path should be empty when archive_name is not set"
  }
}

run "apply_with_name" {
  command = apply

  variables {
    agent_id               = "agent-123"
    paths                  = ["/etc/hosts"]
    archive_name           = "nightly"
    output_dir             = "/tmp/backups"
    compression            = "zstd"
    create_archive_on_stop = true
  }

  assert {
    condition     = output.archive_path == "/tmp/backups/nightly.tar.zst"
    error_message = "archive_path should be computed from archive_name + output_dir + extension"
  }
}
