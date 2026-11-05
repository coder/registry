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
  mock_data "coder_workspace_owner" {
    defaults = {
      id            = "0b6b6a5e-0000-4000-8000-000000000002"
      name          = "owner"
      email         = "owner@example.org"
      session_token = "owner-full-session-token"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 201
      response_body = "{\"key\":\"scoped-id-scoped-secret\"}"
    }
  }
}

override_module {
  target  = module.code-server
  outputs = {}
}

variables {
  namespace       = "coder-workspaces"
  workspace_image = "registry.example.com/coder/workspace:v2.30.0"
  launcher_image  = "registry.example.com/coder/openshell-launcher:0.1.5"
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

override_data {
  target = data.coder_parameter.runtime
  values = { value = "kata-clh" }
}

run "isolated" {
  command = plan

  assert {
    condition     = length(kubernetes_pod_v1.workspace) == 1 && kubernetes_persistent_volume_claim_v1.docker.spec[0].resources[0].requests.storage == "30Gi" && kubernetes_persistent_volume_claim_v1.docker.spec[0].volume_mode == "Block"
    error_message = "A start must create the workspace Pod and a 30Gi block Docker disk."
  }
  assert {
    condition     = keys(yamldecode(local.policy).network_policies) == ["coder"]
    error_message = "Fully isolated must allow only Coder."
  }
  assert {
    condition     = yamldecode(local.policy).network_policies.coder.endpoints[0].host == "coder.example.com" && yamldecode(local.policy).network_policies.coder.endpoints[0].port == 443
    error_message = "The policy must allow the access URL host and port."
  }
  assert {
    condition     = contains([for b in yamldecode(local.policy).network_policies.coder.binaries : b.path], "/usr/local/bin/coder") && contains([for b in yamldecode(local.policy).network_policies.coder.binaries : b.path], "/opt/claude/**")
    error_message = "The agent and Claude Code must reach Coder."
  }
  assert {
    condition     = contains(yamldecode(local.policy).filesystem_policy.read_only, "/usr") && contains(yamldecode(local.policy).filesystem_policy.read_only, "/etc") && contains(yamldecode(local.policy).filesystem_policy.read_write, "/home/coder")
    error_message = "Landlock must keep /usr and /etc read-only and the home writable."
  }
  assert {
    condition     = jsondecode(local.driver_config).docker.mounts[0].source == "coder-home" && jsondecode(local.driver_config).docker.mounts[0].target == "/home/coder"
    error_message = "The driver config must mount the home volume at /home/coder."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == "kata-clh" && kubernetes_pod_v1.workspace[0].spec[0].automount_service_account_token == false
    error_message = "The Pod must run in Kata with no ServiceAccount token."
  }
  assert {
    condition = alltrue([
      kubernetes_pod_v1.workspace[0].spec[0].container[0].name == "launcher",
      kubernetes_pod_v1.workspace[0].spec[0].container[0].security_context[0].run_as_non_root == true,
      kubernetes_pod_v1.workspace[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false,
      kubernetes_pod_v1.workspace[0].spec[0].container[0].security_context[0].capabilities[0].drop[0] == "ALL",
    ])
    error_message = "The launcher container must be hardened."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].container[1].name == "docker" && kubernetes_pod_v1.workspace[0].spec[0].container[1].security_context[0].privileged == true
    error_message = "The Docker daemon must be the second container."
  }
  assert {
    condition     = one([for e in kubernetes_pod_v1.workspace[0].spec[0].container[0].env : e if e.name == "CODER_AGENT_TOKEN"]).value_from[0].secret_key_ref[0].name == kubernetes_secret_v1.agent_token[0].metadata[0].name
    error_message = "The agent token must come from the Secret, not the Pod spec."
  }
  assert {
    condition     = one([for e in kubernetes_pod_v1.workspace[0].spec[0].container[0].env : e.value if e.name == "SANDBOX_NAME"]) == "coder-0b6b6a5e00004" && length(local.sandbox_name) <= 19
    error_message = "The sandbox name must fit the 19 character limit of OpenShell."
  }
  assert {
    condition     = strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "openshell sandbox create") && strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "CODER_AGENT_DERP_ONLY=true")
    error_message = "The launcher must create the sandbox with a DERP-only agent."
  }
  assert {
    condition     = endswith(local.agent_command, "exec /usr/local/bin/coder agent") && startswith(local.agent_command, "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/.")
    error_message = "The sandbox must seed the home and run the agent from the image."
  }
  assert {
    condition     = jsonencode(kubernetes_pod_v1.workspace[0].metadata[0].labels) == jsonencode(local.labels) && !strcontains(jsonencode(local.labels), "owner") && !strcontains(jsonencode(local.labels), "test")
    error_message = "The Pod must not depend on the owner or the workspace name, so a claim does not replace it."
  }
  assert {
    condition     = jsonencode(kubernetes_network_policy_v1.workspace.spec[0].egress[0].to[0].ip_block[0].except) == jsonencode(local.private_cidrs) && jsonencode([for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : "${p.protocol}/${p.port}"]) == jsonencode(["TCP/443", "UDP/53", "TCP/53"])
    error_message = "The NetworkPolicy must allow public addresses on 443 and DNS only, with no private ranges."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].ingress) == 0 && contains(kubernetes_network_policy_v1.workspace.spec[0].policy_types, "Ingress")
    error_message = "The NetworkPolicy must block all ingress."
  }
}

run "github" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = [for e in yamldecode(local.policy).network_policies.profile.endpoints : e.host] == local.github_hosts && alltrue([for e in yamldecode(local.policy).network_policies.profile.endpoints : e.port == 443])
    error_message = "GitHub only must allow the GitHub hosts on 443."
  }
  assert {
    condition     = yamldecode(local.policy).network_policies.profile.binaries[0].path == "/**"
    error_message = "Profile hosts must be open to every program."
  }
  assert {
    condition     = length(module.git-clone) == 0
    error_message = "With no git_repo_url, nothing is cloned."
  }
}

run "development" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "development" }
  }

  assert {
    condition     = alltrue([for h in ["registry.npmjs.org", "pypi.org", "proxy.golang.org", "github.com"] : contains([for e in yamldecode(local.policy).network_policies.profile.endpoints : e.host], h)])
    error_message = "GitHub and package registries must allow GitHub, npm, PyPI, and Go."
  }
}

run "custom" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"Example.com\", \"**.wikipedia.org\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\", \"22\", \"22\"]" }
  }

  assert {
    condition     = [for e in yamldecode(local.policy).network_policies.profile.endpoints : "${e.host}:${e.port}"] == ["example.com:443", "example.com:22", "**.wikipedia.org:443", "**.wikipedia.org:22"]
    error_message = "Custom must allow each typed host on each port once, in lowercase."
  }
  assert {
    condition     = keys(yamldecode(local.policy).network_policies) == ["coder", "profile"]
    error_message = "Custom must keep the Coder rule."
  }
  assert {
    condition     = length(data.coder_parameter.custom_problems) == 0 && !contains(keys(data.coder_workspace_preset.profile), "custom")
    error_message = "Valid Custom fields must show no problems, and Custom has no preset."
  }
  assert {
    condition     = contains([for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : p.port], "22")
    error_message = "The NetworkPolicy must allow the Custom ports."
  }
}

run "custom_rejects_ip_and_cluster_names" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"1.2.3.4\", \"kubernetes.default.svc\", \"*.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
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
    values = { value = "[\"example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[]" }
  }

  expect_failures = [terraform_data.custom_check]
}

run "git_clone" {
  command = plan

  variables {
    git_repo_url = "https://github.com/coder/coder"
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "development" }
  }

  assert {
    condition     = length(module.git-clone) == 1
    error_message = "GitHub and package registries must clone git_repo_url."
  }
}

run "git_clone_skips_fully_isolated" {
  command = plan

  variables {
    git_repo_url = "https://github.com/coder/coder"
  }

  assert {
    condition     = length(module.git-clone) == 0
    error_message = "Fully isolated cannot reach GitHub, so it must not clone."
  }
}

run "stop_keeps_docker_disk" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 0
      transition  = "stop"
      access_url  = "https://coder.example.com"
    }
  }

  assert {
    condition     = length(kubernetes_pod_v1.workspace) == 0 && length(kubernetes_secret_v1.agent_token) == 0 && kubernetes_persistent_volume_claim_v1.docker.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-docker"
    error_message = "Stop must delete the Pod and the token, and keep the Docker disk."
  }
}

run "kata" {
  command = plan

  variables {
    runtimes = "kata-qemu, kata-clh"
  }
  override_data {
    target = data.coder_parameter.runtime
    values = { value = "kata-clh" }
  }

  assert {
    condition     = [for o in data.coder_parameter.runtime.option : o.value] == ["kata-qemu", "kata-clh"] && data.coder_parameter.runtime.default == "kata-qemu"
    error_message = "Kernel isolation must offer the listed runtimes, with the first as the default."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == "kata-clh"
    error_message = "The runtime parameter must set the RuntimeClass of the Pod."
  }
  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.profile : p.parameters.runtime == "kata-qemu"])
    error_message = "Presets must set the first runtime, so a claim does not change an immutable parameter."
  }
}

run "rejects_gvisor" {
  command = plan

  variables {
    runtimes = "gvisor"
  }

  expect_failures = [var.runtimes]
}

run "rejects_no_runtimes" {
  command = plan

  variables {
    runtimes = " "
  }

  expect_failures = [var.runtimes]
}

run "presets" {
  command = plan

  assert {
    condition     = keys(data.coder_workspace_preset.profile) == ["development", "github", "isolated"]
    error_message = "Every fixed profile must have a preset."
  }
  assert {
    condition     = data.coder_workspace_preset.profile["isolated"].default == true && alltrue([for p in data.coder_workspace_preset.profile : one(p.prebuilds).instances == 1])
    error_message = "Fully isolated must be the default preset, and each preset must have one prebuild."
  }
}

run "no_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 0
  }

  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.profile : length(p.prebuilds) == 0])
    error_message = "prebuild_instances = 0 must turn prebuilds off."
  }
}

run "port_from_access_url" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "http://203.0.113.10:8080"
    }
  }

  assert {
    condition     = yamldecode(local.policy).network_policies.coder.endpoints[0].host == "203.0.113.10" && yamldecode(local.policy).network_policies.coder.endpoints[0].port == 8080
    error_message = "The Coder rule must use the access URL port."
  }
  assert {
    condition     = contains([for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : p.port], "8080")
    error_message = "The NetworkPolicy must allow the access URL port."
  }
}

run "coder_egress_cidrs" {
  command = plan

  variables {
    coder_egress_cidrs = ["10.0.5.10/32"]
  }

  assert {
    condition     = kubernetes_network_policy_v1.workspace.spec[0].egress[0].to[0].ip_block[0].cidr == "10.0.5.10/32" && jsonencode([for p in kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports : p.port]) == jsonencode(["443"])
    error_message = "coder_egress_cidrs must allow the Coder server on the access URL port."
  }
}

run "rejects_ipv6_coder_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["2001:db8::/64"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "image_pull_secret" {
  command = plan

  variables {
    image_pull_secret = "registry-creds"
  }

  assert {
    condition     = one([for e in kubernetes_pod_v1.workspace[0].spec[0].container[0].env : e.value if e.name == "DOCKER_CONFIG"]) == "/docker-config" && one([for v in kubernetes_pod_v1.workspace[0].spec[0].volume : v if v.name == "docker-config"]).secret[0].secret_name == "registry-creds"
    error_message = "image_pull_secret must give the launcher a Docker config from the Secret."
  }
}

run "ai_gateway_scoped_token" {
  command = apply

  assert {
    condition     = nonsensitive(coder_env.anthropic_auth_token[0].value) == "scoped-id-scoped-secret" && coder_env.anthropic_base_url[0].value == "https://coder.example.com/api/v2/aibridge/anthropic"
    error_message = "Claude Code must get the scoped token and the AI Gateway URL, not the owner's session token."
  }
  assert {
    condition     = jsonencode(jsondecode(data.http.ai_gateway_token[0].request_body).scopes) == jsonencode(["user:read_personal"]) && nonsensitive(data.http.ai_gateway_token[0].request_headers["Coder-Session-Token"]) == "owner-full-session-token"
    error_message = "The build must create a token with only the user:read_personal scope, using the owner's session token."
  }
}

run "ai_gateway_prebuild" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
      is_prebuild = true
    }
  }

  assert {
    condition     = length(data.http.ai_gateway_token) == 0 && length(coder_env.anthropic_auth_token) == 0
    error_message = "A prebuild must not create a token. The claim does."
  }
}

run "ai_gateway_off" {
  command = plan

  variables {
    enable_ai_gateway = false
  }

  assert {
    condition     = length(data.http.ai_gateway_token) == 0 && length(coder_env.anthropic_auth_token) == 0 && length(coder_env.anthropic_base_url) == 0
    error_message = "enable_ai_gateway = false must not create a token."
  }
}

run "claude_code_off" {
  command = plan

  variables {
    enable_claude_code = false
  }

  assert {
    condition     = length(coder_app.claude) == 0 && length(data.http.ai_gateway_token) == 0
    error_message = "enable_claude_code = false must remove the app and the token."
  }
}

run "rejects_latest_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com/coder/workspace:latest"
  }

  expect_failures = [var.workspace_image]
}

run "rejects_untagged_launcher_image" {
  command = plan

  variables {
    launcher_image = "registry.example.com/coder/openshell-launcher"
  }

  expect_failures = [var.launcher_image]
}

run "rejects_small_docker_disk" {
  command = plan

  variables {
    docker_disk_size = 2
  }

  expect_failures = [var.docker_disk_size]
}

run "rejects_empty_namespace" {
  command = plan

  variables {
    namespace = " "
  }

  expect_failures = [var.namespace]
}
