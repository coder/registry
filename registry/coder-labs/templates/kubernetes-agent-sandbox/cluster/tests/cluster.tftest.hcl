mock_provider "kubernetes" {}

variables {
  namespace          = "coder-workspaces"
  workspace_image    = "registry.example.com/coder/workspace:v2.30.0"
  coder_access_url   = "https://coder.example.com"
  coder_egress_cidrs = ["203.0.113.10/32"]
}

run "defaults" {
  command = plan

  assert {
    condition     = toset(keys(kubernetes_manifest.sandbox_template)) == toset(["coder-gvisor", "coder-gvisor-github"]) && toset(keys(kubernetes_manifest.warm_pool)) == toset(["coder-gvisor", "coder-gvisor-github"])
    error_message = "The defaults must create a Fully isolated and a GitHub only gVisor pool."
  }
  assert {
    condition     = length(kubernetes_namespace_v1.workspaces) == 1 && length(kubernetes_cluster_role_v1.crd_read) == 1 && length(kubernetes_manifest.guardrail) == 0
    error_message = "The defaults must create the namespace and the CRD read role, and no guardrail."
  }
  assert {
    condition     = local.coder_port == 443
    error_message = "An https access URL without a port must use 443."
  }
  assert {
    condition     = kubernetes_manifest.warm_pool["coder-gvisor"].manifest.spec.replicas == 1 && kubernetes_manifest.warm_pool["coder-gvisor"].manifest.spec.sandboxTemplateRef.name == "coder-gvisor"
    error_message = "A pool must keep warm_pool_replicas sandboxes from its SandboxTemplate."
  }
}

run "network_rules" {
  command = plan

  variables {
    git_repo_url = "https://github.com/coder/coder"
  }

  assert {
    condition     = length(kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.networkPolicy.egress) == 1 && kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.networkPolicy.egress[0].ports[0].port == 443
    error_message = "A Fully isolated pool must allow only the Coder server."
  }
  assert {
    condition     = length(kubernetes_manifest.sandbox_template["coder-gvisor-github"].manifest.spec.networkPolicy.egress) == 3
    error_message = "A GitHub only pool must allow Coder, the GitHub ranges, and DNS."
  }
  assert {
    condition     = contains([for e in kubernetes_manifest.sandbox_template["coder-gvisor-github"].manifest.spec.podTemplate.spec.containers[0].env : e.name], "GIT_REPO_URL") && !contains([for e in kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.containers[0].env : e.name], "GIT_REPO_URL")
    error_message = "Only the GitHub only pool must clone git_repo_url."
  }
  assert {
    condition     = !strcontains(local.pool_command, "github.com") && strcontains(local.pool_command, "kill -TERM 1") && strcontains(local.pool_command, "exec /usr/local/bin/coder agent")
    error_message = "The pool script must read the repository from env and include the policy check."
  }
}

run "runtime_matrix" {
  command = plan

  variables {
    runtimes = ["gvisor", "kata-qemu", "kata-clh"]
  }

  assert {
    condition     = length(kubernetes_manifest.warm_pool) == 6 && kubernetes_manifest.sandbox_template["coder-kata-clh-github"].manifest.spec.podTemplate.spec.runtimeClassName == "kata-clh"
    error_message = "There must be one pool for each runtime and scratch profile."
  }
}

run "no_scratch" {
  command = plan

  variables {
    scratch_profiles = []
  }

  assert {
    condition     = length(kubernetes_manifest.warm_pool) == 0 && length(kubernetes_role_v1.provisioner.rule) > 0
    error_message = "No scratch profiles must create no pools, but still the Role."
  }
}

run "http_port" {
  command = plan

  variables {
    coder_access_url = "http://203.0.113.10"
  }

  assert {
    condition     = local.coder_port == 80 && !can(kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.hostAliases)
    error_message = "An http access URL must use 80, and an IP needs no host alias."
  }
}

run "explicit_port" {
  command = plan

  variables {
    coder_access_url = "https://coder.example.com:8443"
  }

  assert {
    condition     = local.coder_port == 8443
    error_message = "The port of the access URL must win over the scheme."
  }
}

run "port_override" {
  command = plan

  variables {
    coder_egress_port = 3000
  }

  assert {
    condition     = local.coder_port == 3000
    error_message = "coder_egress_port must override the access URL."
  }
}

run "host_alias" {
  command = plan

  variables {
    coder_host_ip = "203.0.113.10"
  }

  assert {
    condition     = kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.hostAliases[0].hostnames == ["coder.example.com"]
    error_message = "A host name access URL with coder_host_ip must map the host name."
  }
}

run "no_access_url" {
  command = plan

  variables {
    coder_access_url = ""
  }

  assert {
    condition     = local.coder_port == 443 && !contains([for e in kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.containers[0].env : e.name], "CODER_AGENT_URL")
    error_message = "Without coder_access_url, the pools must use port 443 and take the agent URL from the claim."
  }
  assert {
    condition     = strcontains(local.pool_command, "CODER_AGENT_URL=\"$(cat /podinfo/url)\"") && contains([for i in kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.volumes[2].downwardAPI.items : i.path], "url")
    error_message = "The pool must read the agent URL from the claim annotation."
  }
}

run "host_ip_needs_access_url" {
  command = plan

  variables {
    coder_access_url = ""
    coder_host_ip    = "203.0.113.10"
  }

  expect_failures = [kubernetes_manifest.sandbox_template]
}

run "existing_namespace" {
  command = plan

  variables {
    create_namespace = false
    grant_crd_read   = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.workspaces) == 0 && kubernetes_role_v1.provisioner.metadata[0].namespace == "coder-workspaces" && length(kubernetes_cluster_role_v1.crd_read) == 0
    error_message = "create_namespace = false must use the existing namespace."
  }
}

run "guardrail" {
  command = plan

  variables {
    enable_guardrail = true
  }

  assert {
    condition     = kubernetes_manifest.guardrail[0].manifest.spec.tier == "Admin" && kubernetes_manifest.guardrail[0].manifest.spec.egress[0].ports[0].portNumber.port == 443
    error_message = "The guardrail must be an Admin tier policy that allows the Coder port."
  }
}

run "no_policy_gate" {
  command = plan

  variables {
    network_policy_gate = false
  }

  assert {
    condition     = endswith(local.pool_command, "exec /usr/local/bin/coder agent") && !strcontains(local.pool_command, "KUBERNETES_SERVICE_HOST")
    error_message = "Without the gate, the pool must start the agent directly."
  }
}

run "coder_variables" {
  command = plan

  variables {
    runtimes = ["kata-clh", "gvisor"]
  }

  assert {
    condition     = yamldecode(output.coder_variables).runtimes == "kata-clh,gvisor" && yamldecode(output.coder_variables).coder_egress_port == "443" && yamldecode(output.coder_variables).namespace == "coder-workspaces"
    error_message = "coder_variables must have the template variables as strings."
  }
}

run "dns_servers_and_clone_limit" {
  command = plan

  variables {
    dns_servers  = ["10.0.0.2"]
    git_repo_url = "https://github.com/coder/coder"
  }

  assert {
    condition     = kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.dnsConfig.nameservers == tolist(["10.0.0.2"]) && kubernetes_manifest.sandbox_template["coder-gvisor-github"].manifest.spec.networkPolicy.egress[2].to[0].ipBlock.cidr == "10.0.0.2/32"
    error_message = "The pools must use dns_servers for DNS and its NetworkPolicy rule."
  }
  assert {
    condition     = strcontains(local.pool_command, "failed 5 times") && kubernetes_manifest.sandbox_template["coder-gvisor"].manifest.spec.podTemplate.spec.containers[0].command[0] == "bash"
    error_message = "The pool script must stop retrying the clone, and run with bash."
  }
  assert {
    condition     = yamldecode(output.coder_variables).dns_servers == "10.0.0.2"
    error_message = "coder_variables must pass dns_servers to the template."
  }
}

run "rejects_latest_image" {
  command = plan

  variables {
    workspace_image = "registry.example.com/coder/workspace:latest"
  }

  expect_failures = [var.workspace_image]
}

run "rejects_url_with_path" {
  command = plan

  variables {
    coder_access_url = "https://coder.example.com/app"
  }

  expect_failures = [var.coder_access_url]
}

run "rejects_unknown_runtime" {
  command = plan

  variables {
    runtimes = ["runc"]
  }

  expect_failures = [var.runtimes]
}
