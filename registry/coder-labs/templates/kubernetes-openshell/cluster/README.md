# Cluster setup for kubernetes-openshell

A cluster administrator sets up the cluster once. The Terraform configuration in this directory creates the workspace namespace, and a Role and RoleBinding for the Coder provisioner. The provisioner can manage Pods, disks, Secrets, and NetworkPolicies in this namespace only.

Each workspace runs its own OpenShell gateway, so there is no gateway, controller, or Helm chart to install.

## 1. Install Kata

The template runs each workspace Pod in a Kata microVM, because the Docker daemon in the Pod is privileged. Add a node group with `/dev/kvm`, and install Kata with a RuntimeClass named `kata-clh` or `kata-qemu`. See [Install the runtimes](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-agent-sandbox/cluster/README.md#2-install-the-runtimes) in the agent-sandbox template. List the RuntimeClasses in the template's `runtimes` variable.

## 2. Apply

Run Terraform from this directory with an account that can create namespaces and RBAC:

```sh
terraform init
terraform apply -var namespace=coder-workspaces
```

Set `namespace` to the namespace for workspaces, and use the same value in the template. If the namespace exists already, set `create_namespace = false`. If the Coder provisioner does not run as the `coder` ServiceAccount in the `coder` namespace, set `provisioner_service_account`.

Keep the Terraform state. Terraform needs it to change or remove the setup later.

## Removal

- Changing `create_namespace` from `true` to `false` deletes the namespace and every workspace in it. To stop managing an existing namespace, run `terraform state rm 'kubernetes_namespace_v1.workspaces[0]'` first.
- `terraform destroy` removes everything this configuration created, including the namespace if it created it.
