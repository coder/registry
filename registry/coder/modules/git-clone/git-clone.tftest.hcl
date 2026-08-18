# Tests for git-clone module

run "creates_clone_script_for_repository_url" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    url      = "https://github.com/coder/coder"
  }

  assert {
    condition     = length(coder_script.git_clone) == 1
    error_message = "A clone script should be created when a repository URL is provided"
  }

  assert {
    condition     = coder_script.git_clone[0].agent_id == "test-agent-id"
    error_message = "Clone script agent ID should match the input variable"
  }
}

run "skips_clone_script_for_empty_url" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    url      = ""
  }

  assert {
    condition     = length(coder_script.git_clone) == 0
    error_message = "No clone script should be created when the repository URL is empty"
  }

  assert {
    condition     = output.folder_name == "" && output.repo_dir == ""
    error_message = "folder_name and repo_dir should be empty when there is no repository and no folder name"
  }
}

run "reports_explicit_folder_name_without_url" {
  command = plan

  variables {
    agent_id    = "test-agent-id"
    url         = ""
    base_dir    = "/tmp"
    folder_name = "project"
  }

  assert {
    condition     = length(coder_script.git_clone) == 0
    error_message = "No clone script should be created when the repository URL is empty"
  }

  assert {
    condition     = output.folder_name == "project" && output.repo_dir == "/tmp/project"
    error_message = "An explicit folder name should still be reported in the outputs"
  }
}

run "skips_clone_script_for_whitespace_url" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    url      = "   "
  }

  assert {
    condition     = length(coder_script.git_clone) == 0
    error_message = "No clone script should be created when the repository URL is only whitespace"
  }

  assert {
    condition     = output.folder_name == "" && output.repo_dir == ""
    error_message = "folder_name and repo_dir should be empty when there is no repository and no folder name"
  }
}
