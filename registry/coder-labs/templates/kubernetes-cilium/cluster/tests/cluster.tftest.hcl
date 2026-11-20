mock_provider "kubernetes" {}

variables {
  namespace = "coder-workspaces"
}

run "creates_namespace_and_role" {
  command = plan

  assert {
    condition     = length(kubernetes_namespace_v1.workspaces) == 1 && kubernetes_namespace_v1.workspaces[0].metadata[0].name == "coder-workspaces"
    error_message = "The namespace must be created by default."
  }
  assert {
    condition     = kubernetes_role_binding_v1.provisioner.subject[0].name == "coder" && kubernetes_role_binding_v1.provisioner.subject[0].namespace == "coder"
    error_message = "The Role must be bound to the Coder Helm chart's ServiceAccount by default."
  }
  assert {
    condition     = toset(kubernetes_role_v1.provisioner.rule[0].resources) == toset(["pods", "persistentvolumeclaims", "secrets"]) && toset(kubernetes_role_v1.provisioner.rule[1].resources) == toset(["ciliumnetworkpolicies"])
    error_message = "The provisioner must manage only the objects that the template creates, and no cluster-wide policy."
  }
}

run "baseline_denies_the_namespace" {
  command = plan

  assert {
    condition     = kubernetes_manifest.baseline.manifest.kind == "CiliumClusterwideNetworkPolicy" && kubernetes_manifest.baseline.manifest.spec.endpointSelector.matchLabels["k8s:io.kubernetes.pod.namespace"] == "coder-workspaces"
    error_message = "The baseline must select every Pod in the namespace."
  }
  assert {
    condition     = kubernetes_manifest.baseline.manifest.spec.enableDefaultDeny.ingress && kubernetes_manifest.baseline.manifest.spec.enableDefaultDeny.egress
    error_message = "The baseline must deny ingress and egress by default."
  }
  assert {
    condition     = contains(kubernetes_manifest.baseline.manifest.spec.egressDeny[0].toCIDR, "169.254.169.254/32")
    error_message = "The baseline must always deny cloud metadata."
  }
}

run "existing_namespace" {
  command = plan

  variables {
    create_namespace = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.workspaces) == 0 && kubernetes_role_v1.provisioner.metadata[0].namespace == "coder-workspaces"
    error_message = "create_namespace = false must use the namespace as is."
  }
}

run "no_crd_read" {
  command = plan

  variables {
    grant_crd_read = false
  }

  assert {
    condition     = length(kubernetes_cluster_role_v1.crd_read) == 0 && length(kubernetes_cluster_role_binding_v1.crd_read) == 0
    error_message = "grant_crd_read = false must create no ClusterRole."
  }
}

run "rejects_bad_namespace" {
  command = plan

  variables {
    namespace = "Coder_Workspaces"
  }

  expect_failures = [var.namespace]
}
