mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "00000000-0000-4000-8000-000000000001"
      name        = "test"
      access_url  = "https://203.0.113.10"
      start_count = 0
      transition  = "stop"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      id            = "00000000-0000-4000-8000-000000000002"
      name          = "tester"
      session_token = ""
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "aws" {}
mock_provider "http" {}
mock_provider "time" {}
mock_provider "random" {}

override_data {
  target = data.coder_parameter.profile
  values = { value = "isolated" }
}

variables {
  workspace_image    = "registry.example.com/workspace:v1"
  proxy_image        = "registry.example.com/proxy:v1"
  coder_egress_cidrs = ["203.0.113.10/32"]
  aws_region         = "us-east-1"
}

run "defaults_to_nitro" {
  command = plan
  assert {
    condition     = var.sandbox_runtime_class == "isolated-sandbox"
    error_message = "The Nitro template must use the Nitro Sandbox RuntimeClass by default."
  }
}

run "nitro_workspace_with_proxy" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "00000000-0000-4000-8000-000000000001"
      name        = "test"
      access_url  = "https://203.0.113.10"
      start_count = 1
      transition  = "start"
    }
  }
  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }
  override_data {
    target = data.coder_parameter.egress_bundles
    values = { value = "[\"github\"]" }
  }
  override_module {
    target  = module.code-server
    outputs = {}
  }

  assert {
    condition     = local.nitro_sandbox && local.workspace_requests.cpu == "2" && local.workspace_requests.memory == "4Gi" && kubernetes_deployment_v1.workspace[0].spec[0].template[0].spec[0].runtime_class_name == "isolated-sandbox"
    error_message = "The workspace Pod must use Nitro and request its full VM size."
  }
  assert {
    condition     = local.proxy && length(kubernetes_deployment_v1.proxy) == 1 && length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 2 && contains(local.proxy_hosts, "github.com")
    error_message = "An egress profile must create a separate proxy and limit workspace egress."
  }
  assert {
    condition = (
      kubernetes_deployment_v1.workspace[0].spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"] == "8Gi" &&
      one([for v in kubernetes_deployment_v1.workspace[0].spec[0].template[0].spec[0].volume : v.empty_dir[0].size_limit if v.name == "tmp"]) == "2Gi" &&
      kubernetes_deployment_v1.proxy[0].spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"] == "256Mi"
    )
    error_message = "The workspace and proxy must have ephemeral-storage limits, and /tmp a size limit."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.demo[0].data["firewall-demo.sh"], "no GitHub external auth in this template")
    error_message = "Without external auth, the authenticated GitHub probes must report n/a."
  }
}

# The README's example ValidatingAdmissionPolicy admits only Pods that match
# these fields. If this fails, update the policy in the README with the change.
# The policy's spec.nodeName rule is not checked here: the provider computes
# node_name, so a plan cannot read it.
run "pods_meet_the_readme_placement_policy" {
  command = plan

  variables {
    node_pool = "coder.com/pool=agent-egress"
  }
  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "00000000-0000-4000-8000-000000000001"
      name        = "test"
      access_url  = "https://203.0.113.10"
      start_count = 1
      transition  = "start"
    }
  }
  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }
  override_data {
    target = data.coder_parameter.egress_bundles
    values = { value = "[\"github\"]" }
  }
  override_module {
    target  = module.code-server
    outputs = {}
  }

  assert {
    condition = alltrue([
      for pod in [
        kubernetes_deployment_v1.workspace[0].spec[0].template[0].spec[0],
        kubernetes_deployment_v1.proxy[0].spec[0].template[0].spec[0],
        ] : alltrue([
          for term in pod.affinity[0].node_affinity[0].required_during_scheduling_ignored_during_execution[0].node_selector_term :
          anytrue([
            for e in term.match_expressions :
            e.key == "coder.com/pool" && e.operator == "In" && jsonencode(e.values) == jsonencode(["agent-egress"])
          ])
      ])
    ])
    error_message = "Every node selector term of both Pods must require coder.com/pool In [agent-egress]."
  }
  assert {
    condition = (
      kubernetes_deployment_v1.workspace[0].spec[0].template[0].spec[0].runtime_class_name == "isolated-sandbox" &&
      kubernetes_deployment_v1.workspace[0].spec[0].template[0].metadata[0].labels["coder.com/role"] == "workspace" &&
      kubernetes_deployment_v1.proxy[0].spec[0].template[0].metadata[0].labels["coder.com/role"] == "proxy"
    )
    error_message = "The workspace Pod must use isolated-sandbox, and only the proxy Pod may carry the coder.com/role=proxy exemption label."
  }
}

run "firewall_demo_uses_the_github_credential_safely" {
  command = plan

  variables {
    github_external_auth_id = "github"
  }
  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "00000000-0000-4000-8000-000000000001"
      name        = "test"
      access_url  = "https://203.0.113.10"
      start_count = 1
      transition  = "start"
    }
  }
  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }
  override_data {
    target = data.coder_parameter.egress_bundles
    values = { value = "[\"github\"]" }
  }
  override_module {
    target  = module.code-server
    outputs = {}
  }

  assert {
    condition = (
      strcontains(kubernetes_config_map_v1.demo[0].data["firewall-demo.sh"], "GITHUB_AUTH_ID=\"github\"") &&
      strcontains(kubernetes_config_map_v1.demo[0].data["firewall-demo.sh"], "-H @-") &&
      strcontains(kubernetes_config_map_v1.demo[0].data["firewall-demo.sh"], "0000000000000000000000000000000000000000")
    )
    error_message = "The demo must pass the token on stdin and use write probes that cannot succeed."
  }
}

run "bucket_host_needs_identity" {
  command = plan
  variables {
    artifacts_bucket = "example-artifacts"
  }
  assert {
    condition     = local.bucket_host == ""
    error_message = "Do not offer an S3 host when the workspace has no AWS identity."
  }
}

run "rejects_squid_directive_in_host" {
  command = plan
  variables {
    extra_allowed_hosts = "example.com\nhttp_access allow all"
  }
  expect_failures = [var.extra_allowed_hosts]
}

run "rejects_squid_directive_in_dns" {
  command = plan
  variables {
    dns_servers = "8.8.8.8\nhttp_access allow all"
  }
  expect_failures = [var.dns_servers]
}

run "rejects_demo_command_in_organization" {
  command = plan
  variables {
    github_org = "$(touch /tmp/injected)"
  }
  expect_failures = [var.github_org]
}

run "rejects_demo_command_in_bucket" {
  command = plan
  variables {
    artifacts_bucket = "$(touch /tmp/injected)"
  }
  expect_failures = [var.artifacts_bucket]
}

run "rejects_invalid_kiro_region" {
  command = plan
  variables {
    kiro_region = "us-east-1\nhttp_access allow all"
  }
  expect_failures = [var.kiro_region]
}

run "accepts_public_hosts_and_dns" {
  command = plan
  variables {
    extra_allowed_hosts = "api.example.com, files.example.org"
    dns_servers         = "8.8.8.8, 1.1.1.1"
  }
  assert {
    condition     = jsonencode(local.extra_hosts) == jsonencode(["api.example.com", "files.example.org"]) && jsonencode(local.dns_servers) == jsonencode(["8.8.8.8", "1.1.1.1"])
    error_message = "Valid host names and DNS servers must reach the proxy configuration."
  }
}

run "rejects_squid_directive_in_region" {
  command = plan
  variables {
    aws_region = "us-east-1\nhttp_access allow all"
  }
  expect_failures = [var.aws_region]
}

run "kiro_is_opt_in" {
  command = plan

  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }

  assert {
    condition     = contains(keys(local.offered_bundles), "kiro") && !contains(local.default_egress_bundles, "kiro")
    error_message = "Kiro sends model traffic outside AI Gateway, so its bundle must be offered but not chosen by default."
  }
}

run "start_revokes_earlier_tokens_before_minting" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "00000000-0000-4000-8000-000000000001"
      name        = "test"
      access_url  = "https://203.0.113.10"
      start_count = 1
      transition  = "start"
      is_prebuild = false
    }
  }
  override_data {
    target = data.coder_workspace_owner.me
    values = {
      id            = "00000000-0000-4000-8000-000000000002"
      name          = "tester"
      session_token = "owner-session-token"
    }
  }
  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }
  override_data {
    target = data.coder_parameter.egress_bundles
    values = { value = "[\"github\"]" }
  }
  override_module {
    target  = module.code-server
    outputs = {}
  }

  assert {
    condition     = length(terraform_data.revoke_ai_gateway_tokens) == 1 && length(data.http.ai_gateway_token) == 1 && var.ai_gateway_token_lifetime_hours == 8
    error_message = "A start must revoke the workspace's earlier tokens and mint one with an 8 hour default lifetime."
  }
}

run "stop_mints_no_token" {
  command = plan

  override_data {
    target = data.coder_parameter.profile
    values = { value = "workspace-agents" }
  }

  assert {
    condition     = length(terraform_data.revoke_ai_gateway_tokens) == 0 && length(data.http.ai_gateway_token) == 0 && length(coder_env.anthropic_auth_token) == 0
    error_message = "A stop has no owner credentials, so it must mint no token and pass none to the workspace."
  }
}
