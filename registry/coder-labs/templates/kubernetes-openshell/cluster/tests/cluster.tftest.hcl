mock_provider "kubernetes" {}

mock_provider "helm" {}

override_data {
  target = data.kubernetes_secret_v1.client_tls
  values = {
    data = {
      "ca.crt"  = "test-ca"
      "tls.crt" = "test-crt"
      "tls.key" = "test-key"
    }
  }
}

variables {
  namespace = "coder-workspaces"
}

run "defaults" {
  command = plan

  assert {
    condition     = helm_release.gateway.version == "0.1.5" && yamldecode(helm_release.gateway.values[0]).server.sandboxNamespace == "coder-workspaces" && yamldecode(helm_release.gateway.values[0]).server.sandboxUid == 1000
    error_message = "The gateway must put sandboxes in the workspace namespace and run them as uid 1000."
  }
  assert {
    condition     = yamldecode(helm_release.gateway.values[0]).server.drivers.kubernetes.allowDriverConfig == true
    error_message = "The gateway must accept the driver config that mounts the home disk."
  }
  assert {
    condition     = jsonencode(nonsensitive(keys(kubernetes_secret_v1.sandbox_ca.data))) == jsonencode(["ca.crt"])
    error_message = "The supervisor Secret must hold only the CA, no key."
  }
  assert {
    condition     = kubernetes_role_binding_v1.provisioner.subject[0].name == "coder" && toset(kubernetes_role_v1.provisioner.rule[0].resources) == toset(["pods", "persistentvolumeclaims", "secrets"])
    error_message = "The provisioner must manage only launcher Pods, home disks, and token Secrets."
  }
  assert {
    condition     = kubernetes_secret_v1.launcher_tls.metadata[0].namespace == "coder-workspaces" && kubernetes_secret_v1.launcher_tls.metadata[0].name == "openshell-launcher-tls" && jsonencode(nonsensitive(sort(keys(kubernetes_secret_v1.launcher_tls.data)))) == jsonencode(["ca.crt", "tls.crt", "tls.key"])
    error_message = "The launcher bundle must land in the workspace namespace with the name that the template mounts."
  }
  assert {
    condition     = strcontains(output.coder_variables, "https://openshell.openshell.svc.cluster.local:8080")
    error_message = "The output must have the gateway URL."
  }
  assert {
    condition     = length(kubernetes_labels.runtime) == 0
    error_message = "With no runtimes, no RuntimeClass is labeled."
  }
}

run "kata" {
  command = plan

  variables {
    runtimes = ["kata-clh"]
  }

  assert {
    condition     = kubernetes_labels.runtime["kata-clh"].labels["openshell.ai/sandbox-attachable"] == "true"
    error_message = "A listed runtime must get the label that OpenShell admits."
  }
  assert {
    condition     = strcontains(output.coder_variables, "runtimes: \"kata-clh\"") || strcontains(output.coder_variables, "\"runtimes\": \"kata-clh\"")
    error_message = "The output must have the runtimes for the template."
  }
}

run "gateway_elsewhere" {
  command = plan

  variables {
    gateway_namespace = "sandbox-gateway"
    gateway_name      = "openshell-coder"
  }

  assert {
    condition     = helm_release.gateway.name == "openshell-coder" && helm_release.gateway.namespace == "sandbox-gateway" && yamldecode(helm_release.gateway.values[0]).fullnameOverride == "openshell-coder"
    error_message = "The gateway must use the given name and namespace."
  }
  assert {
    condition     = strcontains(output.coder_variables, "https://openshell-coder.sandbox-gateway.svc.cluster.local:8080")
    error_message = "The gateway URL must follow the name and namespace."
  }
}

run "rejects_gvisor" {
  command = plan

  variables {
    runtimes = ["gvisor"]
  }

  expect_failures = [var.runtimes]
}

run "rejects_bad_namespace" {
  command = plan

  variables {
    namespace = "Coder_Workspaces"
  }

  expect_failures = [var.namespace]
}
