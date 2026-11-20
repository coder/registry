mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      id          = "11111111-1111-4111-8111-111111111111"
      name        = "openshift-test"
      start_count = 1
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      id    = "22222222-2222-4222-8222-222222222222"
      name  = "developer"
      email = "developer@example.com"
    }
  }
  mock_data "coder_parameter" {
    defaults = { value = "2" }
  }
}

mock_provider "kubernetes" {
  mock_resource "kubernetes_persistent_volume_claim_v1" {
    defaults = {
      spec = {
        storage_class_name = "cluster-default"
      }
    }
  }
}

variables {
  namespace = "workspace-test"
}

run "default_storage_class" {
  command = apply
  # Create a fresh PVC independently of the explicit-class lifecycle below.
  state_key = "default-storage-class"

  assert {
    condition     = var.storage_class_name == ""
    error_message = "The optional StorageClass must have a non-null default for Coder template import."
  }

  assert {
    # The mock supplies this computed value only when configuration omits it.
    condition     = kubernetes_persistent_volume_claim_v1.home.spec[0].storage_class_name == "cluster-default"
    error_message = "The home PVC must let the cluster select its default StorageClass."
  }
}

run "restricted_workspace" {
  command = apply

  variables {
    storage_class_name = "workspace-storage"
  }

  assert {
    condition = (
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].security_context[0].run_as_user == null &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].security_context[0].run_as_group == null &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].security_context[0].fs_group == null &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].security_context[0].run_as_user == null &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].security_context[0].run_as_group == null
    )
    error_message = "OpenShift must assign the UID, GID, and volume group."
  }

  assert {
    condition = (
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].security_context[0].run_as_non_root &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].security_context[0].seccomp_profile[0].type == "RuntimeDefault" &&
      !kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop == tolist(["ALL"])
    )
    error_message = "The pod must satisfy restricted-v2 without elevated capabilities."
  }

  assert {
    condition = (
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].command == null &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].args == tolist(["sh", "-c", coder_agent.main.init_script])
    )
    error_message = "Agent bootstrap must preserve the image's arbitrary UID entrypoint."
  }

  assert {
    condition = (
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].volume_mount[0].mount_path == "/home/user" &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].volume[0].persistent_volume_claim[0].claim_name == kubernetes_persistent_volume_claim_v1.home.metadata[0].name &&
      kubernetes_deployment_v1.main[0].spec[0].strategy[0].type == "Recreate"
    )
    error_message = "The agent's home must use the persistent PVC with a single-pod rollout."
  }

  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.spec[0].storage_class_name == "workspace-storage"
    error_message = "An explicit StorageClass must be used when creating the home PVC."
  }

  assert {
    condition = (
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].service_account_name == "default" &&
      !kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].automount_service_account_token &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].node_selector["kubernetes.io/arch"] == coder_agent.main.arch
    )
    error_message = "Workspace must use the unprivileged account without API credentials and match agent architecture."
  }
}

run "stop_workspace" {
  command = apply

  override_data {
    target = data.coder_workspace.me
    values = {
      id          = "11111111-1111-4111-8111-111111111111"
      name        = "openshift-test"
      start_count = 0
    }
  }

  override_data {
    target = data.coder_parameter.home_disk_size
    values = { value = "20" }
  }

  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.spec[0].resources[0].requests["storage"] == "2Gi" && kubernetes_persistent_volume_claim_v1.home.spec[0].storage_class_name == "workspace-storage"
    error_message = "Existing storage must not be replaced by changes to disk or StorageClass defaults."
  }

  assert {
    condition     = length(kubernetes_deployment_v1.main) == 0 && length(module.code-server) == 0
    error_message = "Stopping must remove ephemeral compute and apps."
  }

  assert {
    condition     = kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-11111111-1111-4111-8111-111111111111-home"
    error_message = "Stopping must keep the same persistent home volume."
  }
}

run "restart_workspace" {
  command = apply

  assert {
    condition     = length(kubernetes_deployment_v1.main) == 1 && kubernetes_persistent_volume_claim_v1.home.metadata[0].name == "coder-11111111-1111-4111-8111-111111111111-home"
    error_message = "Restart must recreate compute and reuse the same home PVC."
  }
}

run "custom_image_and_architecture" {
  command = apply

  variables {
    arch  = "arm64"
    image = "registry.example.com/workspace:tested"
  }

  assert {
    condition = (
      coder_agent.main.arch == "arm64" &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].node_selector["kubernetes.io/arch"] == "arm64" &&
      kubernetes_deployment_v1.main[0].spec[0].template[0].spec[0].container[0].image == var.image
    )
    error_message = "Image overrides and ARM64 scheduling must agree with the agent."
  }
}

run "invalid_project" {
  command = plan
  variables {
    namespace = "Invalid_Project"
  }
  expect_failures = [var.namespace]
}

run "unsupported_architecture" {
  command = plan
  variables {
    arch = "ppc64le"
  }
  expect_failures = [var.arch]
}

run "empty_image" {
  command = plan
  variables {
    image = " "
  }
  expect_failures = [var.image]
}
