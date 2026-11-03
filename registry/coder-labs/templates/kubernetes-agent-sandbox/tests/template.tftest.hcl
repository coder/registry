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
  coder_egress_cidrs = ["203.0.113.10/32"]
}

override_data {
  target = data.coder_parameter.network_isolation
  values = { value = "isolated" }
}

override_data {
  target = data.coder_parameter.runtime
  values = { value = "gvisor" }
}

override_data {
  target = data.coder_parameter.home
  values = { value = "persistent" }
}

run "persistent_isolated" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.sandbox) == 1 && length(kubernetes_manifest.claim) == 0
    error_message = "A persistent home must create a Sandbox and no SandboxClaim."
  }
  assert {
    condition     = length(kubernetes_persistent_volume_claim_v1.home) == 1 && kubernetes_persistent_volume_claim_v1.home[0].spec[0].resources[0].requests.storage == "10Gi"
    error_message = "A persistent home must create a 10Gi PVC."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.runtimeClassName == "gvisor"
    error_message = "The runtime parameter must set the RuntimeClass."
  }
  assert {
    condition = alltrue([
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.automountServiceAccountToken == false,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.runAsNonRoot == true,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.runAsUser == 1000,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.fsGroup == 1000,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.fsGroupChangePolicy == "OnRootMismatch",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.securityContext.seccompProfile.type == "RuntimeDefault",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].securityContext.allowPrivilegeEscalation == false,
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].securityContext.capabilities.drop[0] == "ALL",
      kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].imagePullPolicy == "IfNotPresent",
    ])
    error_message = "The workspace Pod must be hardened."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env[0].valueFrom.secretKeyRef.name == kubernetes_secret_v1.agent_token[0].metadata[0].name
    error_message = "The agent token must come from the Secret."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].env[1].value == "https://203.0.113.10"
    error_message = "CODER_AGENT_URL must be the access URL."
  }
  assert {
    condition     = strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "exec /usr/local/bin/coder agent\n") && strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "kill -TERM 1") && strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "KUBERNETES_SERVICE_HOST")
    error_message = "The container must run the policy gate and then the agent from the image."
  }
  assert {
    condition     = strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "%%{time_connect}") && strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "NetworkPolicy is no longer enforced")
    error_message = "The gate must check the TCP connection, and keep checking after the agent starts."
  }
  assert {
    condition     = startswith(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "[ -e /home/coder/.bashrc ] || cp -an /etc/skel/.")
    error_message = "A new home must get the image's dotfiles."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.metadata.labels["com.coder.workspace.id"] == kubernetes_network_policy_v1.workspace[0].spec[0].pod_selector[0].match_labels["com.coder.workspace.id"]
    error_message = "The NetworkPolicy must select the workspace Pod."
  }
  assert {
    condition     = length(kubernetes_network_policy_v1.workspace[0].spec[0].egress) == 1 && kubernetes_network_policy_v1.workspace[0].spec[0].egress[0].to[0].ip_block[0].cidr == "203.0.113.10/32" && kubernetes_network_policy_v1.workspace[0].spec[0].egress[0].ports[0].port == "443"
    error_message = "Fully isolated must allow only the Coder server."
  }
  assert {
    condition     = !can(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases)
    error_message = "An IP access URL needs no host alias."
  }
}

run "persistent_github" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = length(kubernetes_network_policy_v1.workspace[0].spec[0].egress) == 3
    error_message = "GitHub only must allow Coder, the GitHub ranges, and DNS."
  }
  assert {
    condition     = [for t in kubernetes_network_policy_v1.workspace[0].spec[0].egress[1].to : t.ip_block[0].cidr] == local.github_cidrs
    error_message = "GitHub only must allow the GitHub ranges."
  }
  assert {
    condition     = [for t in kubernetes_network_policy_v1.workspace[0].spec[0].egress[2].to : t.ip_block[0].cidr] == ["8.8.8.8/32", "1.1.1.1/32"]
    error_message = "GitHub only must allow DNS to the public resolvers only."
  }
  assert {
    condition     = length(module.git-clone) == 0
    error_message = "An empty git_repo_url must clone nothing."
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
    error_message = "Fully isolated cannot reach Git hosts, so it must not clone."
  }
}

run "persistent_internet" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "internet" }
  }

  assert {
    condition     = kubernetes_network_policy_v1.workspace[0].spec[0].egress[1].to[0].ip_block[0].cidr == "0.0.0.0/0" && toset(kubernetes_network_policy_v1.workspace[0].spec[0].egress[1].to[0].ip_block[0].except) == toset(local.private_cidrs)
    error_message = "Public internet must exclude private ranges and cloud metadata."
  }
  assert {
    condition     = [for p in kubernetes_network_policy_v1.workspace[0].spec[0].egress[1].ports : p.port] == ["443", "80"]
    error_message = "Public internet must allow only ports 443 and 80."
  }
}

run "kata" {
  command = plan

  override_data {
    target = data.coder_parameter.runtime
    values = { value = "kata-qemu" }
  }

  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.runtimeClassName == "kata-qemu"
    error_message = "Kata QEMU must set the kata-qemu RuntimeClass."
  }
}

run "scratch" {
  command = plan

  override_data {
    target = data.coder_parameter.home
    values = { value = "scratch" }
  }
  override_data {
    target = data.coder_parameter.runtime
    values = { value = "kata-clh" }
  }

  assert {
    condition     = length(kubernetes_manifest.claim) == 1 && length(kubernetes_manifest.sandbox) == 0
    error_message = "A scratch home must claim from the warm pool."
  }
  assert {
    condition     = kubernetes_manifest.claim[0].manifest.spec.warmPoolRef.name == "coder-kata-clh"
    error_message = "The claim must use the warm pool of the runtime."
  }
  assert {
    condition     = length(kubernetes_persistent_volume_claim_v1.home) == 0 && length(kubernetes_network_policy_v1.workspace) == 0 && length(kubernetes_secret_v1.agent_token) == 0
    error_message = "A scratch home needs no PVC, Secret, or Terraform NetworkPolicy."
  }
  assert {
    condition     = kubernetes_manifest.claim[0].manifest.spec.additionalPodMetadata.annotations["coder.com/agent-url"] == "https://203.0.113.10"
    error_message = "The claim must pass the access URL to the pooled Pod."
  }
}

run "scratch_github" {
  command = plan

  override_data {
    target = data.coder_parameter.home
    values = { value = "scratch" }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  assert {
    condition     = kubernetes_manifest.claim[0].manifest.spec.warmPoolRef.name == "coder-gvisor-github"
    error_message = "GitHub only must claim from the GitHub only warm pool."
  }
}

run "scratch_rejects_public_internet" {
  command = plan

  override_data {
    target = data.coder_parameter.home
    values = { value = "scratch" }
  }
  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "internet" }
  }

  expect_failures = [kubernetes_manifest.claim]
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

  assert {
    condition     = length(kubernetes_manifest.sandbox) == 0 && length(kubernetes_secret_v1.agent_token) == 0
    error_message = "Stop must delete the Sandbox and the token Secret."
  }
  assert {
    condition     = length(kubernetes_persistent_volume_claim_v1.home) == 1 && length(kubernetes_network_policy_v1.workspace) == 1
    error_message = "Stop must keep the home disk."
  }
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

  expect_failures = [kubernetes_manifest.sandbox]
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
      access_url  = "https://coder.example.com:8443/"
    }
  }

  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases[0].ip == "203.0.113.10" && kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.hostAliases[0].hostnames[0] == "coder.example.com"
    error_message = "coder_host_ip must map the access URL host in /etc/hosts."
  }
}

run "presets" {
  command = plan

  assert {
    condition     = length(data.coder_workspace_preset.persistent) == 3 && alltrue([for p in data.coder_workspace_preset.persistent : p.parameters.runtime == "gvisor" && p.parameters.home == "persistent"])
    error_message = "There must be one gVisor persistent preset per network profile."
  }
  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.persistent : one(p.prebuilds).instances == 1])
    error_message = "Each persistent preset must prebuild prebuild_instances workspaces."
  }
  assert {
    condition     = data.coder_workspace_preset.persistent["isolated"].default == true && data.coder_workspace_preset.persistent["github"].default == false
    error_message = "Fully isolated must be the default preset."
  }
  assert {
    condition     = toset(keys(data.coder_workspace_preset.scratch)) == toset(["isolated", "github"]) && alltrue([for p in data.coder_workspace_preset.scratch : p.parameters.home == "scratch" && length(p.prebuilds) == 0])
    error_message = "Fully isolated and GitHub only must each have a scratch preset without prebuilds."
  }
}

run "no_prebuilds" {
  command = plan

  variables {
    prebuild_instances = 0
  }

  assert {
    condition     = alltrue([for p in data.coder_workspace_preset.persistent : length(p.prebuilds) == 0])
    error_message = "prebuild_instances = 0 must turn prebuilds off."
  }
}

run "no_policy_gate" {
  command = plan

  variables {
    network_policy_gate = false
  }

  assert {
    condition     = !strcontains(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "KUBERNETES_SERVICE_HOST")
    error_message = "network_policy_gate = false must remove the gate."
  }
  assert {
    condition     = endswith(kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[2], "exec /usr/local/bin/coder agent")
    error_message = "Without the gate, the container must exec the agent."
  }
}

run "rejects_latest_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com/coder/workspace:latest"
  }

  expect_failures = [var.workspace_image]
}

run "rejects_empty_namespace" {
  command = plan

  variables {
    namespace = " "
  }

  expect_failures = [var.namespace]
}

run "rejects_bad_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["coder.example.com"]
  }

  expect_failures = [var.coder_egress_cidrs]
}

run "rejects_bad_port" {
  command = plan

  variables {
    coder_egress_port = 70000
  }

  expect_failures = [var.coder_egress_port]
}

run "rejects_negative_prebuilds" {
  command = plan

  variables {
    prebuild_instances = -1
  }

  expect_failures = [var.prebuild_instances]
}

run "rejects_untagged_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com:5000/coder/workspace"
  }

  expect_failures = [var.workspace_image]
}

run "accepts_digest_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com:5000/coder/workspace@sha256:32e560b86242d4ac65e7a777953ed3ec991d4db8368e24dea7e9ea0817a3410e"
  }

  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].image == var.workspace_image
    error_message = "A digest must be accepted."
  }
}

run "rejects_ipv6_cidr" {
  command = plan

  variables {
    coder_egress_cidrs = ["2001:db8::1/128"]
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

run "ai_gateway_env" {
  command = plan

  assert {
    condition     = coder_env.anthropic_base_url[0].value == "https://203.0.113.10/api/v2/aibridge/anthropic"
    error_message = "ANTHROPIC_BASE_URL must point at the Coder AI Gateway."
  }

  assert {
    condition     = length(coder_env.anthropic_auth_token) == 1 && length(coder_env.claude_disable_autoupdater) == 1
    error_message = "The AI Gateway token and DISABLE_AUTOUPDATER must be set on start."
  }
}

run "ai_gateway_scoped_token" {
  command = apply

  assert {
    condition     = nonsensitive(coder_env.anthropic_auth_token[0].value) == "scoped-id-scoped-secret"
    error_message = "ANTHROPIC_AUTH_TOKEN must be the scoped token, not the owner's session token."
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
    error_message = "A prebuild must not create a token. The claim build does."
  }
}

run "ai_gateway_off" {
  command = plan

  variables {
    enable_ai_gateway = false
  }

  assert {
    condition     = length(coder_env.anthropic_base_url) == 0 && length(coder_env.anthropic_auth_token) == 0 && length(data.http.ai_gateway_token) == 0
    error_message = "No AI Gateway env or token when enable_ai_gateway is false."
  }
}

run "claude_code_off" {
  command = plan

  variables {
    enable_claude_code = false
  }

  assert {
    condition     = length(coder_app.claude) == 0 && length(coder_env.claude_disable_autoupdater) == 0 && length(coder_env.anthropic_base_url) == 0 && length(coder_env.anthropic_auth_token) == 0
    error_message = "No Claude Code app or env when enable_claude_code is false."
  }
}

run "dns_servers" {
  command = plan

  override_data {
    target = data.coder_parameter.network_isolation
    values = { value = "github" }
  }

  variables {
    dns_servers = "10.0.0.2, 10.0.0.3"
  }

  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.dnsConfig.nameservers == tolist(["10.0.0.2", "10.0.0.3"])
    error_message = "The Pod must use dns_servers."
  }
  assert {
    condition     = kubernetes_network_policy_v1.workspace[0].spec[0].egress[2].to[0].ip_block[0].cidr == "10.0.0.2/32"
    error_message = "The NetworkPolicy must allow DNS to dns_servers."
  }
  assert {
    condition     = kubernetes_manifest.sandbox[0].manifest.spec.podTemplate.spec.containers[0].command[0] == "bash"
    error_message = "The agent command must run with bash."
  }
}

run "rejects_ipv6_dns" {
  command = plan

  variables {
    dns_servers = "2001:4860:4860::8888"
  }

  expect_failures = [var.dns_servers]
}

run "runtimes_variable" {
  command = plan

  variables {
    runtimes = "kata-clh, gvisor"
  }

  assert {
    condition     = [for o in data.coder_parameter.runtime.option : o.value] == ["kata-clh", "gvisor"] && data.coder_parameter.runtime.default == "kata-clh"
    error_message = "The runtime options must follow runtimes, with the first as the default."
  }
  assert {
    condition     = data.coder_workspace_preset.persistent["isolated"].parameters.runtime == "kata-clh" && data.coder_workspace_preset.scratch["github"].parameters.runtime == "kata-clh"
    error_message = "The presets must use the first runtime."
  }
}

run "no_scratch_profiles" {
  command = plan

  variables {
    scratch_profiles = ""
  }

  assert {
    condition     = length(data.coder_workspace_preset.scratch) == 0 && length(data.coder_parameter.home.option) == 1
    error_message = "Empty scratch_profiles must hide scratch homes."
  }
}

run "rejects_unknown_runtime" {
  command = plan

  variables {
    runtimes = "gvisor,runc"
  }

  expect_failures = [var.runtimes]
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
    condition     = kubernetes_network_policy_v1.workspace[0].spec[0].egress[0].ports[0].port == "8080"
    error_message = "The Coder port must come from the access URL."
  }
}

run "port_override" {
  command = plan

  variables {
    coder_egress_port = 3000
  }

  assert {
    condition     = kubernetes_network_policy_v1.workspace[0].spec[0].egress[0].ports[0].port == "3000"
    error_message = "coder_egress_port must override the access URL."
  }
}
