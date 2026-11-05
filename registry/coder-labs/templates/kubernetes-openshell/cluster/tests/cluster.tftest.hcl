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
    condition     = toset(kubernetes_role_v1.provisioner.rule[0].resources) == toset(["pods", "persistentvolumeclaims", "secrets"])
    error_message = "The provisioner must manage only the objects that the template creates."
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

run "rejects_bad_namespace" {
  command = plan

  variables {
    namespace = "Coder_Workspaces"
  }

  expect_failures = [var.namespace]
}
