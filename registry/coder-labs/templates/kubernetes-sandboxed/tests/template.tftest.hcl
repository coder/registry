mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://203.0.113.10"
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
  namespace          = "coder-workspaces"
  workspace_image    = "registry.example.com/coder/workspace:v2.30.0"
  proxy_image        = "registry.example.com/coder/egress-proxy:v1"
  coder_egress_cidrs = ["203.0.113.10/32"]
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

override_resource {
  target          = terraform_data.pod_name
  override_during = plan
  values          = { id = "1a2b3c4d-0000-4000-8000-000000000003" }
}

run "isolated" {
  command = plan

  assert {
    condition     = length(kubernetes_pod_v1.workspace) == 1 && length(kubernetes_pod_v1.proxy) == 0 && length(kubernetes_service_v1.proxy) == 0 && length(kubernetes_network_policy_v1.proxy) == 0
    error_message = "Fully isolated must create the workspace Pod and no proxy."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.spec[0].resources[0].requests.storage == "10Gi"
    error_message = "The home must be a 10Gi PVC."
  }
  assert {
    condition = alltrue([
      kubernetes_pod_v1.workspace[0].spec[0].automount_service_account_token == false,
      kubernetes_pod_v1.workspace[0].spec[0].enable_service_links == false,
      kubernetes_pod_v1.workspace[0].spec[0].security_context[0].run_as_non_root == true,
      kubernetes_pod_v1.workspace[0].spec[0].security_context[0].run_as_user == "1000",
      kubernetes_pod_v1.workspace[0].spec[0].security_context[0].fs_group == "1000",
      kubernetes_pod_v1.workspace[0].spec[0].security_context[0].fs_group_change_policy == "OnRootMismatch",
      kubernetes_pod_v1.workspace[0].spec[0].security_context[0].seccomp_profile[0].type == "RuntimeDefault",
      kubernetes_pod_v1.workspace[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false,
      kubernetes_pod_v1.workspace[0].spec[0].container[0].security_context[0].capabilities[0].drop[0] == "ALL",
      kubernetes_pod_v1.workspace[0].spec[0].container[0].image_pull_policy == "IfNotPresent",
    ])
    error_message = "The workspace Pod must be hardened."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == null
    error_message = "With no runtimes, the Pod must use the node's container runtime."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].container[0].env[0].value_from[0].secret_key_ref[0].name == kubernetes_secret_v1.agent_token[0].metadata[0].name
    error_message = "The agent token must come from the Secret."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].container[0].env[1].value == "https://203.0.113.10"
    error_message = "CODER_AGENT_URL must be the access URL."
  }
  assert {
    condition     = length(kubernetes_pod_v1.workspace[0].spec[0].container[0].env) == 3
    error_message = "Fully isolated must set no proxy variables."
  }
  assert {
    condition     = strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "exec /usr/local/bin/coder agent\n") && strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "kill -TERM 1") && strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "KUBERNETES_SERVICE_HOST")
    error_message = "The container must run the policy gate and then the agent from the image."
  }
  assert {
    condition     = startswith(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/.")
    error_message = "A new home must get the image's dotfiles."
  }
  assert {
    condition     = kubernetes_network_policy_v1.workspace.spec[0].pod_selector[0].match_labels == kubernetes_pod_v1.workspace[0].metadata[0].labels
    error_message = "The workspace NetworkPolicy must select the workspace Pod."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 1 && kubernetes_network_policy_v1.workspace.spec[0].egress[0].to[0].ip_block[0].cidr == "203.0.113.10/32" && kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports[0].port == "443"
    error_message = "Fully isolated must allow only the Coder server."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].ingress) == 0
    error_message = "The workspace must get no ingress."
  }
  assert {
    condition     = length(kubernetes_pod_v1.workspace[0].spec[0].host_aliases) == 0
    error_message = "An IP access URL needs no host alias."
  }
  assert {
    condition     = tolist(kubernetes_pod_v1.workspace[0].spec[0].dns_config[0].nameservers) == tolist(["127.0.0.1"]) && kubernetes_pod_v1.workspace[0].spec[0].dns_policy == "None"
    error_message = "The workspace must have no DNS, and lookups must fail at once."
  }
  assert {
    condition     = jsonencode(kubernetes_pod_v1.workspace[0].metadata[0].labels) == jsonencode(local.workspace_labels) && !strcontains(jsonencode(local.workspace_labels), "owner") && !strcontains(jsonencode(local.workspace_labels), "test")
    error_message = "The Pod must not depend on the owner or the workspace name, so a claim does not replace it."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-1a2b3c4d-pod"
    error_message = "Pod names must end in -pod, after a part that is new for every Pod."
  }
}

run "github" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = length(kubernetes_pod_v1.proxy) == 1 && length(kubernetes_service_v1.proxy) == 1 && length(kubernetes_config_map_v1.proxy) == 1
    error_message = "GitHub only must create a proxy."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace.spec[0].egress) == 2 && kubernetes_network_policy_v1.workspace.spec[0].egress[1].to[0].pod_selector[0].match_labels == kubernetes_pod_v1.proxy[0].metadata[0].labels && kubernetes_network_policy_v1.workspace.spec[0].egress[1].ports[0].port == "3128"
    error_message = "The workspace must reach Coder and its own proxy only."
  }
  assert {
    condition     = kubernetes_network_policy_v1.proxy[0].spec[0].ingress[0].from[0].pod_selector[0].match_labels == kubernetes_pod_v1.workspace[0].metadata[0].labels
    error_message = "Only the workspace must reach the proxy."
  }
  assert {
    condition     = kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].to[0].ip_block[0].cidr == "0.0.0.0/0" && contains(kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].to[0].ip_block[0].except, "169.254.0.0/16") && [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["443"]
    error_message = "The proxy must reach only public addresses on 443."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "acl allowed dstdomain -n github.com api.github.com") && !strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "registry.npmjs.org")
    error_message = "GitHub only must allow the GitHub hosts only."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny !CONNECT\n")
    error_message = "GitHub only must deny plain HTTP."
  }
  assert {
    condition     = [for e in kubernetes_pod_v1.workspace[0].spec[0].container[0].env : e.name] == ["CODER_AGENT_TOKEN", "CODER_AGENT_URL", "CODER_AGENT_AUTH", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"]
    error_message = "The workspace must get the proxy variables."
  }
  assert {
    condition     = local.proxy_env["no_proxy"] == "localhost,127.0.0.1,::1,203.0.113.10"
    error_message = "The workspace must reach Coder without the proxy."
  }
  assert {
    condition     = kubernetes_pod_v1.proxy[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true && kubernetes_pod_v1.proxy[0].spec[0].automount_service_account_token == false
    error_message = "The proxy Pod must be hardened."
  }
  assert {
    condition     = kubernetes_pod_v1.proxy[0].spec[0].security_context[0].run_as_user == "31" && kubernetes_pod_v1.proxy[0].spec[0].security_context[0].run_as_non_root == true && kubernetes_pod_v1.proxy[0].spec[0].container[0].security_context[0].capabilities[0].drop[0] == "ALL" && kubernetes_pod_v1.proxy[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "The proxy Pod must run as squid with no capabilities."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny manager\n") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny ip6_literal\n")
    error_message = "The proxy must deny the cache manager and IPv6 literals."
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
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "registry.npmjs.org") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "pypi.org") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "proxy.golang.org")
    error_message = "GitHub and package registries must allow npm, PyPI, and Go."
  }
}

run "internet" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "internet" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "dstdom_regex -n -i [a-z]$")
    error_message = "Public internet must allow any host name."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["443", "80"]
    error_message = "Public internet must allow 443 and 80."
  }
  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "acl private_dst dst") && strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access allow allowed !private_dst")
    error_message = "The proxy must refuse private addresses."
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
    values = { value = "[\"Example.com\", \"*.wikipedia.org\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\", \"80\"]" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "acl allowed dstdomain -n example.com .wikipedia.org")
    error_message = "Custom must allow the typed hosts, in lowercase, with *. written as a leading dot."
  }
  assert {
    condition     = length(data.coder_parameter.custom_problems) == 0
    error_message = "Valid Custom fields must show no problems."
  }
  assert {
    condition     = length(data.coder_workspace_preset.profile) == 4 && !contains(keys(data.coder_workspace_preset.profile), "custom")
    error_message = "Custom must have no preset."
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

run "custom_http_only" {
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
    values = { value = "[\"80\", \"80\"]" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny CONNECT\n") && !strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "http_access deny !CONNECT\n")
    error_message = "Custom with port 80 only must deny HTTPS tunnels and allow plain HTTP."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.proxy[0].spec[0].egress[0].ports : p.port] == ["80"]
    error_message = "The proxy must reach only port 80, once."
  }
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
    values = { value = "github" }
  }

  assert {
    condition     = length(module.git-clone) == 1
    error_message = "GitHub only must clone git_repo_url."
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

run "stop_keeps_home" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 0
      transition  = "stop"
      access_url  = "https://203.0.113.10"
    }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = length(kubernetes_pod_v1.workspace) == 0 && length(kubernetes_pod_v1.proxy) == 0 && length(kubernetes_secret_v1.agent_token) == 0
    error_message = "Stop must delete the Pods and the token."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home" && length(kubernetes_service_v1.proxy) == 1
    error_message = "Stop must keep the home disk and the proxy Service."
  }
}

run "runtimes" {
  command = plan

  variables {
    runtimes = "gvisor, kata-clh"
  }
  override_data {
    target = data.coder_parameter.runtime
    values = { value = "gvisor" }
  }

  assert {
    condition     = [for o in data.coder_parameter.runtime[0].option : o.value] == ["none", "gvisor", "kata-clh"]
    error_message = "Kernel isolation must offer None and then the listed runtimes."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == "gvisor"
    error_message = "The runtime parameter must set the RuntimeClass."
  }
  assert {
    condition     = kubernetes_pod_v1.proxy == []
    error_message = "Fully isolated must create no proxy with any runtime."
  }
  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.profile : p.parameters.runtime == "none"])
    error_message = "Presets must set the runtime, so a claim does not change an immutable parameter."
  }
}

run "no_runtimes" {
  command = plan

  assert {
    condition     = length(data.coder_parameter.runtime) == 0 && alltrue([for p in data.coder_workspace_preset.profile : !contains(keys(p.parameters), "runtime")])
    error_message = "With no runtimes, Kernel isolation must not show, and presets must not set it."
  }
}

run "rejects_unknown_runtime" {
  command = plan

  variables {
    runtimes = "runc"
  }

  expect_failures = [var.runtimes]
}

run "host_name_needs_ip" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
    }
  }

  expect_failures = [kubernetes_pod_v1.workspace]
}

run "host_name_alias" {
  command = plan

  variables {
    coder_host_ip = "203.0.113.10"
  }
  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://coder.example.com"
    }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].host_aliases[0].ip == "203.0.113.10" && tolist(kubernetes_pod_v1.workspace[0].spec[0].host_aliases[0].hostnames) == tolist(["coder.example.com"])
    error_message = "A host name access URL must map to coder_host_ip."
  }
  assert {
    condition     = local.proxy_env["NO_PROXY"] == "localhost,127.0.0.1,::1,coder.example.com"
    error_message = "The agent must reach Coder without the proxy."
  }
}

run "presets" {
  command = plan

  assert {
    condition     = keys(data.coder_workspace_preset.profile) == ["development", "github", "internet", "isolated"]
    error_message = "Every fixed profile must have a preset."
  }
  assert {
    condition     = data.coder_workspace_preset.profile["isolated"].default == true && data.coder_workspace_preset.profile["github"].default == false
    error_message = "Fully isolated must be the default preset."
  }
  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.profile : one(p.prebuilds).instances == 1])
    error_message = "Each preset must have one prebuild by default."
  }
}

run "no_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 0
  }

  assert {
    condition     = length(data.coder_workspace_preset.profile["isolated"].prebuilds) == 0
    error_message = "prebuild_instances = 0 must turn prebuilds off."
  }
}

run "no_policy_gate" {
  command = plan

  variables {
    network_policy_gate = false
  }

  assert {
    condition     = endswith(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "\nexec /usr/local/bin/coder agent") && !strcontains(kubernetes_pod_v1.workspace[0].spec[0].container[0].command[2], "KUBERNETES_SERVICE_HOST")
    error_message = "network_policy_gate = false must start the agent at once."
  }
}

run "dns_servers" {
  command = plan

  variables {
    dns_servers = "10.0.0.2, 10.0.0.3"
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = strcontains(kubernetes_config_map_v1.proxy[0].data["squid.conf"], "dns_nameservers 10.0.0.2 10.0.0.3\n")
    error_message = "The proxy must use dns_servers."
  }
  assert {
    condition     = [for t in kubernetes_network_policy_v1.proxy[0].spec[0].egress[1].to : t.ip_block[0].cidr] == ["10.0.0.2/32", "10.0.0.3/32"]
    error_message = "The proxy must reach only dns_servers for DNS."
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
    condition     = kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports[0].port == "8080"
    error_message = "The Coder port must come from the access URL."
  }
}

run "port_override" {
  command = plan

  variables {
    coder_egress_port = 7080
  }

  assert {
    condition     = kubernetes_network_policy_v1.workspace.spec[0].egress[0].ports[0].port == "7080"
    error_message = "coder_egress_port must override the access URL port."
  }
}

run "rejects_bad_port" {
  command = plan

  variables {
    coder_egress_port = 70000
  }

  expect_failures = [var.coder_egress_port]
}

run "rejects_negative_port" {
  command = plan

  variables {
    coder_egress_port = -1
  }

  expect_failures = [var.coder_egress_port]
}

run "ai_gateway_scoped_token" {
  command = apply

  assert {
    condition     = nonsensitive(coder_env.anthropic_auth_token[0].value) == "scoped-id-scoped-secret" && coder_env.anthropic_base_url[0].value == "https://203.0.113.10/api/v2/aibridge/anthropic"
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
      access_url  = "https://203.0.113.10"
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

run "rejects_untagged_proxy_image" {
  command = plan

  variables {
    proxy_image = "registry.example.com/coder/egress-proxy"
  }

  expect_failures = [var.proxy_image]
}

run "accepts_digest_image" {
  command = plan

  variables {
    proxy_image = "registry.example.com/coder/egress-proxy@sha256:32e560b86242d4ac65e7a777953ed3ec991d4db8368e24dea7e9ea0817a3410e"
  }

  assert {
    condition     = var.proxy_image != ""
    error_message = "A digest must be accepted."
  }
}

run "rejects_empty_namespace" {
  command = plan

  variables {
    namespace = " "
  }

  expect_failures = [var.namespace]
}

run "rejects_ipv6_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["2001:db8::/64"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "rejects_bad_host_ip" {
  command = plan

  variables {
    coder_host_ip = "coder.example.com"
  }

  expect_failures = [var.coder_host_ip]
}

run "rejects_ipv6_dns" {
  command = plan

  variables {
    dns_servers = "2001:4860:4860::8888"
  }

  expect_failures = [var.dns_servers]
}
