mock_provider "http" {}

override_data {
  target = data.coder_workspace.me
  values = {
    id          = "8a3d1c2e-0000-4000-8000-000000000000"
    access_url  = "https://coder.example.com"
    start_count = 1
    is_prebuild = false
  }
}

override_data {
  target = data.coder_workspace_owner.me
  values = {
    session_token = "owner-session-token"
  }
}

override_data {
  target = data.http.token
  values = {
    status_code   = 201
    response_body = "{\"key\":\"scoped-token\"}"
  }
}

run "mints_scoped_token" {
  command = apply

  variables {
    lifetime_hours = 24
  }

  assert {
    condition     = output.token == "scoped-token"
    error_message = "The output must be the minted token, not the owner session token."
  }

  assert {
    condition     = data.http.token[0].url == "https://coder.example.com/api/v2/users/me/keys/tokens"
    error_message = "The token must be created through the owner's token API."
  }

  assert {
    condition     = jsondecode(data.http.token[0].request_body).scopes == ["user:read_personal"]
    error_message = "The token must request only user:read_personal by default."
  }

  assert {
    condition     = jsondecode(data.http.token[0].request_body).lifetime == 86400000000000
    error_message = "lifetime_hours must be sent to the API in nanoseconds."
  }
}

run "prebuild_gets_no_token" {
  command = apply

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "8a3d1c2e-0000-4000-8000-000000000000"
      access_url  = "https://coder.example.com"
      start_count = 1
      is_prebuild = true
    }
  }

  assert {
    condition     = length(data.http.token) == 0 && output.token == ""
    error_message = "A prebuild must not create a token for the prebuilds user."
  }
}

run "fails_closed_on_api_error" {
  command = apply

  override_data {
    target = data.http.token
    values = {
      status_code   = 403
      response_body = "{\"message\":\"forbidden\"}"
    }
  }

  expect_failures = [data.http.token]
}

run "rejects_full_access_scope" {
  command = plan

  variables {
    scopes = ["coder:all"]
  }

  expect_failures = [var.scopes]
}
