mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
    }
  }
  mock_data "coder_provisioner" {
    defaults = {
      arch = "amd64"
    }
  }
}

mock_provider "restapi" {}

variables {
  kube_token_path = "tests/fixtures/token"
  kube_ca_path    = "tests/fixtures/ca.crt"
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

run "isolated_allows_only_coder" {
  command = plan

  assert {
    condition     = jsondecode(jsondecode(restapi_object.workspace.data).data.hosts) == []
    error_message = "Fully isolated must allow no hosts besides Coder."
  }
  assert {
    condition     = jsondecode(jsondecode(restapi_object.workspace.data).data.ports) == [443]
    error_message = "Fixed profiles must allow port 443 only."
  }
  assert {
    condition     = restapi_object.workspace.path == "/api/v1/namespaces/coder-substrate/configmaps"
    error_message = "The ConfigMap must go to the namespace that coder-bridge reads."
  }
}

run "names_follow_the_workspace_id" {
  command = plan

  assert {
    condition     = jsondecode(restapi_object.workspace.data).metadata.name == "ws-0b6b6a5e-0000-4000-8000-000000000001"
    error_message = "The ConfigMap must be named after the workspace ID, which coder-bridge uses as the actor name."
  }
  assert {
    condition     = local.actor == "ws-0b6b6a5e-0000-4000-8000-000000000001" && length(restapi_object.agent) == 1 && restapi_object.agent[0].path == "/api/v1/namespaces/coder-substrate/secrets"
    error_message = "A started workspace must have one agent Secret, named after the actor."
  }
  assert {
    condition     = !contains(keys(jsondecode(restapi_object.workspace.data).metadata.labels), "com.coder.workspace.owner")
    error_message = "Labels must not include the owner, which changes at a prebuild claim."
  }
}

run "github_profile" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = contains(jsondecode(jsondecode(restapi_object.workspace.data).data.hosts), "github.com") && !contains(jsondecode(jsondecode(restapi_object.workspace.data).data.hosts), "registry.npmjs.org")
    error_message = "GitHub only must allow GitHub and not npm."
  }
}

run "development_profile" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "development" }
  }

  assert {
    condition     = contains(jsondecode(jsondecode(restapi_object.workspace.data).data.hosts), "registry.npmjs.org") && contains(jsondecode(jsondecode(restapi_object.workspace.data).data.hosts), "pypi.org")
    error_message = "GitHub and package registries must allow npm and PyPI."
  }
}

run "stopped_workspace_has_no_token" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      start_count = 0
      transition  = "stop"
    }
  }

  assert {
    condition     = length(restapi_object.agent) == 0
    error_message = "A stopped workspace must have no agent Secret, so coder-bridge suspends the actor."
  }
}

run "custom_hosts_and_ports" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"*.Example.com\", \" github.com \", \"github.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\", \"80\"]" }
  }

  assert {
    condition     = jsondecode(jsondecode(restapi_object.workspace.data).data.hosts) == ["*.example.com", "github.com"]
    error_message = "Custom hosts must be trimmed, lower case, and unique."
  }
  assert {
    condition     = jsondecode(jsondecode(restapi_object.workspace.data).data.ports) == [443, 80]
    error_message = "Custom must use the chosen ports."
  }
  assert {
    condition     = length(data.coder_parameter.custom_problems) == 0
    error_message = "Valid Custom fields must not show the problems field."
  }
}

run "custom_rejects_bad_hosts" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"10.0.0.1\", \"*.com\", \"api.svc\", \"metadata.internal\", \"ok.example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  assert {
    condition     = local.custom_bad == ["10.0.0.1", "*.com", "api.svc", "metadata.internal"]
    error_message = "Custom must reject IP addresses, top-level wildcards, and cluster names."
  }

  expect_failures = [terraform_data.custom_check]
}

run "custom_needs_a_port" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"github.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[]" }
  }

  assert {
    condition     = local.custom_problems == 1
    error_message = "Custom with no port must count one problem."
  }

  expect_failures = [terraform_data.custom_check]
}

run "presets_have_prebuilds" {
  command = plan

  assert {
    condition     = length(data.coder_workspace_preset.profile) == 3 && !contains(keys(data.coder_workspace_preset.profile), "custom")
    error_message = "Every fixed profile, and not Custom, must be a preset."
  }
  assert {
    condition     = one(data.coder_workspace_preset.profile["isolated"].prebuilds).instances == 1
    error_message = "Presets must default to one prebuild."
  }
}

run "prebuilds_off" {
  command = plan

  variables {
    prebuild_instances = 0
  }

  assert {
    condition     = length(data.coder_workspace_preset.profile["isolated"].prebuilds) == 0
    error_message = "prebuild_instances = 0 must turn prebuilds off."
  }
}

run "rejects_fractional_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 1.5
  }

  expect_failures = [var.prebuild_instances]
}

run "rejects_empty_namespace" {
  command = plan

  variables {
    namespace = " "
  }

  expect_failures = [var.namespace]
}
