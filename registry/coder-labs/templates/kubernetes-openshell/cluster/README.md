# Cluster setup for kubernetes-openshell

A cluster administrator sets up the cluster once. The Terraform configuration in this directory creates everything the template needs in the cluster:

- The OpenShell gateway, from its Helm chart, in its own namespace.
- The workspace namespace, where the gateway creates the sandboxes.
- The gateway CA for the supervisor Pods, and the gateway client bundle for the launcher Pods, in the workspace namespace.
- A Role and RoleBinding for the Coder provisioner. It can manage Pods, disks, and Secrets in the workspace namespace only.
- The `openshell.ai/sandbox-attachable=true` label on the Kata RuntimeClasses in `runtimes`, so that OpenShell admits them.

## 1. Install agent-sandbox

The OpenShell Kubernetes driver creates agent-sandbox Sandboxes. Install the controller and the extensions, v1.0.4 or later:

```sh
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.4/sandbox-with-extensions.yaml
```

For Kata, see [Install the runtimes](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-agent-sandbox/cluster/README.md#2-install-the-runtimes) in the agent-sandbox template.

## 2. Apply

Run Terraform from this directory with an account that can create namespaces, RBAC, and Helm releases:

```sh
terraform init
terraform apply -var namespace=coder-workspaces
```

Set `runtimes`, for example `["kata-clh"]`, to offer Kata. Use the same value in the template. If the Coder provisioner does not run as the `coder` ServiceAccount in the `coder` namespace, set `provisioner_service_account`. `openshell_version` pins the Helm chart. Use the same version for the CLI in `build/launcher/Dockerfile`.

Keep the Terraform state. Terraform needs it to change or remove the setup later.

## 3. Push the template with the same values

The `coder_variables` output has the namespace, the gateway URL, and the runtimes as a variables file for `coder templates push`. See the Quick start in the [template README](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/README.md#quick-start).

## Changes and removal

- `terraform destroy` removes the gateway, both namespaces, and every workspace in them. It also removes the label from the RuntimeClasses in `runtimes`.
- Removing a runtime from `runtimes` removes its label, so OpenShell no longer admits it. Remove it from the template first.
