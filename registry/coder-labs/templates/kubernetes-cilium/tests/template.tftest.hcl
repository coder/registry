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

override_module {
  target  = module.git-clone
  outputs = {}
}

variables {
  namespace       = "coder-workspaces"
  workspace_image = "registry.example.com/coder/workspace:v2.30.0"
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

run "isolated_allows_only_coder" {
  command = plan

  assert {
    condition     = kubernetes_manifest.network_policy.manifest.spec.endpointSelector.matchLabels["com.coder.workspace.id"] == "0b6b6a5e-0000-4000-8000-000000000001" && kubernetes_manifest.dns_policy[0].manifest.spec.endpointSelector.matchLabels["com.coder.workspace.id"] == "0b6b6a5e-0000-4000-8000-000000000001"
    error_message = "Both policies must select only this workspace's Pod."
  }
  assert {
    condition     = kubernetes_manifest.network_policy.manifest.spec.enableDefaultDeny.ingress && kubernetes_manifest.network_policy.manifest.spec.enableDefaultDeny.egress
    error_message = "The policy must deny ingress and egress by default."
  }
  assert {
    condition     = jsonencode(local.dns_rules) == jsonencode([{ matchName = "coder.example.com" }])
    error_message = "Fully isolated must answer DNS only for the Coder host."
  }
  assert {
    condition     = length(local.egress) == 1 && jsonencode(local.egress[0]) == jsonencode({ toFQDNs = [{ matchName = "coder.example.com" }], toPorts = [{ ports = [{ port = "443", protocol = "TCP" }] }] })
    error_message = "Fully isolated must allow only the Coder host on 443."
  }
}

run "dns_policy_uses_dns_server" {
  command = plan

  assert {
    condition     = jsonencode(local.dns_egress.toCIDR) == jsonencode(["169.254.169.253/32"]) && length(local.dns_egress.toPorts[0].ports) == 2
    error_message = "DNS must go only to dns_server, on UDP and TCP 53."
  }
  assert {
    condition     = jsonencode(kubernetes_manifest.dns_policy[0].manifest.spec.egress[0].toPorts[0].rules.dns) == jsonencode([{ matchName = "coder.example.com", matchPattern = null }])
    error_message = "The DNS policy must allow only the Coder host name."
  }
}

run "manifest_egress_has_uniform_elements" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"*.example.org\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  variables {
    coder_egress_cidrs = ["10.20.0.0/16"]
  }

  assert {
    condition = jsonencode(kubernetes_manifest.network_policy.manifest.spec.egress) == jsonencode([
      { toCIDR = null, toFQDNs = [{ matchName = "coder.example.com", matchPattern = null }], toPorts = [{ ports = [{ port = "443", protocol = "TCP" }] }] },
      { toCIDR = ["10.20.0.0/16"], toFQDNs = null, toPorts = [{ ports = [{ port = "443", protocol = "TCP" }] }] },
      { toCIDR = null, toFQDNs = [{ matchName = "example.org", matchPattern = null }, { matchName = null, matchPattern = "*.example.org" }], toPorts = [{ ports = [{ port = "443", protocol = "TCP" }] }] },
    ])
    error_message = "Every egress element in the manifest must have the same attributes, with null for the unused ones."
  }
}

run "private_ranges_denied_except_dns" {
  command = plan

  assert {
    condition     = [for d in local.private_deny : d.cidr] == ["10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"]
    error_message = "Every private range must be denied."
  }
  assert {
    condition     = jsonencode([for d in local.private_deny : d.except]) == jsonencode([[], [], ["169.254.169.253/32"], [], []])
    error_message = "Only the DNS server must be cut out, and only from the range that holds it."
  }
}

run "coder_cidr_cut_out_of_deny" {
  command = plan

  variables {
    coder_egress_cidrs = ["10.20.0.0/16"]
    dns_server         = "8.8.8.8"
  }

  assert {
    condition     = jsonencode([for d in local.private_deny : d.except]) == jsonencode([["10.20.0.0/16"], [], [], [], []])
    error_message = "A private Coder range must be cut out of 10.0.0.0/8, and a public DNS server out of nothing."
  }
  assert {
    condition     = jsonencode(local.egress[1].toCIDR) == jsonencode(["10.20.0.0/16"])
    error_message = "The Coder ranges must have an allow rule."
  }
}

run "coder_by_ip" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "https://203.0.113.10:8443"
    }
  }

  assert {
    condition     = jsonencode(local.egress) == jsonencode([{ toCIDR = ["203.0.113.10/32"], toPorts = [{ ports = [{ port = "8443", protocol = "TCP" }] }] }])
    error_message = "An IP access URL must use a CIDR rule with the access URL's port."
  }
  assert {
    condition     = length(kubernetes_manifest.dns_policy) == 0
    error_message = "With no allowed names, the workspace must get no DNS policy."
  }
}

run "coder_by_private_ip" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "http://10.0.1.5:3000"
    }
  }

  assert {
    condition     = jsonencode(local.private_deny[0].except) == jsonencode(["10.0.1.5/32"])
    error_message = "A private access URL address must be cut out of the deny rule."
  }
  assert {
    condition     = local.egress[0].toPorts[0].ports[0].port == "3000"
    error_message = "The Coder port must come from the access URL."
  }
}

run "port_from_http_access_url" {
  command = plan

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "0b6b6a5e-0000-4000-8000-000000000001"
      name        = "test"
      start_count = 1
      transition  = "start"
      access_url  = "http://Coder.Example.com"
    }
  }

  assert {
    condition     = local.egress[0].toPorts[0].ports[0].port == "80" && local.access_host == "coder.example.com"
    error_message = "An http access URL must use port 80, and the host name must be lowercase."
  }
}

run "port_override" {
  command = plan

  variables {
    coder_egress_port = 8443
  }

  assert {
    condition     = local.egress[0].toPorts[0].ports[0].port == "8443"
    error_message = "coder_egress_port must override the access URL port."
  }
}

run "github_profile" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = jsonencode(local.dns_rules) == jsonencode(concat([{ matchName = "coder.example.com" }], [for h in local.github_hosts : { matchName = h }]))
    error_message = "GitHub only must answer DNS for Coder and the GitHub hosts."
  }
  assert {
    condition     = jsonencode(local.egress[1]) == jsonencode({ toFQDNs = [for h in local.github_hosts : { matchName = h }], toPorts = [{ ports = [{ port = "443", protocol = "TCP" }] }] })
    error_message = "GitHub only must allow the GitHub hosts on 443 only."
  }
}

run "internet_profile" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "internet" }
  }

  assert {
    condition     = jsonencode(local.dns_rules) == jsonencode([{ matchPattern = "*" }]) && jsonencode(local.egress[1].toFQDNs) == jsonencode([{ matchPattern = "*" }])
    error_message = "Public internet must allow any name, but only names."
  }
  assert {
    condition     = jsonencode([for p in local.egress[1].toPorts[0].ports : p.port]) == jsonencode(["443", "80"])
    error_message = "Public internet must allow ports 443 and 80."
  }
  assert {
    condition     = length(kubernetes_manifest.network_policy.manifest.spec.egressDeny[0].toCIDRSet) == 5
    error_message = "Public internet must still deny private ranges."
  }
}

run "custom_wildcard" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "custom" }
  }
  override_data {
    target = data.coder_parameter.custom_hosts
    values = { value = "[\"*.example.org\", \"api.example.com\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"80\"]" }
  }

  assert {
    condition     = jsonencode(local.fqdn_selectors) == jsonencode([{ matchName = "api.example.com" }, { matchName = "example.org" }, { matchPattern = "*.example.org" }])
    error_message = "*.example.org must allow example.org and one level below it."
  }
  assert {
    condition     = jsonencode(local.egress[1].toPorts) == jsonencode([{ ports = [{ port = "80", protocol = "TCP" }] }])
    error_message = "Custom must use only the picked ports."
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
    values = { value = "[\"1.1.1.1\", \"kube-dns.kube-system.svc.cluster.local\"]" }
  }
  override_data {
    target = data.coder_parameter.custom_ports
    values = { value = "[\"443\"]" }
  }

  expect_failures = [terraform_data.custom_check]
}

run "pod_defaults" {
  command = plan

  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].dns_policy == "None" && jsonencode(kubernetes_pod_v1.workspace[0].spec[0].dns_config[0].nameservers) == jsonencode(["169.254.169.253"])
    error_message = "The Pod must use only dns_server."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == null && !kubernetes_pod_v1.workspace[0].spec[0].automount_service_account_token
    error_message = "The Pod must use the node's runtime and have no ServiceAccount token."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].metadata[0].labels["com.coder.workspace.id"] == kubernetes_manifest.network_policy.manifest.spec.endpointSelector.matchLabels["com.coder.workspace.id"]
    error_message = "The Pod must carry the label that the policies select."
  }
  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].node_selector["coder.com/pool"] == "cilium" && kubernetes_pod_v1.workspace[0].spec[0].toleration[0].key == "coder.com/pool" && kubernetes_pod_v1.workspace[0].spec[0].toleration[0].value == "cilium" && kubernetes_pod_v1.workspace[0].spec[0].toleration[0].effect == "NoSchedule"
    error_message = "By default, the Pod must run on the Cilium nodes from cluster/cilium-values.yaml and tolerate their taint."
  }
}

run "cilium_on_every_node" {
  command = plan

  variables {
    node_selector = {}
  }

  assert {
    condition     = length(kubernetes_pod_v1.workspace[0].spec[0].node_selector) == 0 && length(kubernetes_pod_v1.workspace[0].spec[0].toleration) == 0
    error_message = "An empty node_selector must set no selector and no toleration."
  }
}

run "sandbox_runtime" {
  command = plan

  variables {
    runtimes = "gvisor"
  }
  override_data {
    target = data.coder_parameter.runtime
    values = { value = "gvisor" }
  }

  assert {
    condition     = kubernetes_pod_v1.workspace[0].spec[0].runtime_class_name == "gvisor"
    error_message = "A picked runtime must set the RuntimeClass."
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
      access_url  = "https://coder.example.com"
    }
  }

  assert {
    condition     = length(kubernetes_pod_v1.workspace) == 0 && length(kubernetes_secret_v1.agent_token) == 0
    error_message = "Stop must delete the Pod and the token."
  }
  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-0b6b6a5e-0000-4000-8000-000000000001-home"
    error_message = "Stop must keep the home disk."
  }
}

run "presets" {
  command = plan

  assert {
    condition     = jsonencode(sort(keys(data.coder_workspace_preset.profile))) == jsonencode(["development", "github", "internet", "isolated"])
    error_message = "Each fixed profile must have a preset."
  }
  assert {
    condition     = data.coder_workspace_preset.profile["isolated"].default && alltrue([for p in data.coder_workspace_preset.profile : one(p.prebuilds).instances == 1])
    error_message = "Fully isolated must be the default, and each preset must keep one prebuild."
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

run "ai_gateway_scoped_token" {
  command = apply

  assert {
    condition     = nonsensitive(coder_env.anthropic_auth_token[0].value) == "scoped-id-scoped-secret" && coder_env.anthropic_base_url[0].value == "https://coder.example.com/api/v2/aibridge/anthropic"
    error_message = "Claude Code must get the scoped token and the AI Gateway URL, not the owner's session token."
  }
  assert {
    condition     = jsonencode(jsondecode(data.http.ai_gateway_token[0].request_body).scopes) == jsonencode(["user:read_personal"])
    error_message = "The build must create a token with only the user:read_personal scope."
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

run "rejects_metadata_dns_server" {
  command = plan

  variables {
    dns_server = "169.254.169.254"
  }

  expect_failures = [var.dns_server]
}

run "rejects_coder_cidr_holding_a_private_range" {
  command = plan

  variables {
    coder_egress_cidrs = ["10.0.0.0/7"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "rejects_cidr_not_in_network_form" {
  command = plan

  variables {
    coder_egress_cidrs = ["10.20.0.5/16"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "rejects_ipv6_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["2001:db8::/64"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "rejects_unknown_runtime" {
  command = plan

  variables {
    runtimes = "gvisor,runc"
  }

  expect_failures = [var.runtimes]
}

run "rejects_latest_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com/coder/workspace:latest"
  }

  expect_failures = [var.workspace_image]
}
