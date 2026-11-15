# Cluster setup for kubernetes-cilium

A cluster administrator sets up the cluster once:

1. Run Cilium on the nodes for workspaces.
2. Apply the Terraform configuration in this directory. It creates the workspace namespace, a Role and RoleBinding for the Coder provisioner, a ClusterRole to read CRDs, and the baseline policy.

## 1. Install Cilium

If Cilium is already the network plugin on every node, skip to step 2. It needs the DNS proxy, which is on by default.

On Amazon EKS with VPC CNI, Cilium can run in chaining mode on its own node group. VPC CNI still gives Pods their addresses, and the other nodes do not change.

1. Create a managed node group with an AL2023 AMI, the label `coder.com/pool=cilium`, and these taints:
   - `coder.com/pool=cilium:NoSchedule`, so that only workspaces run there.
   - `node.cilium.io/agent-not-ready=true:NoExecute`, so that no Pod starts before Cilium is ready. Cilium removes it.

   EKS Auto Mode nodes cannot run Cilium, because their network plugin is managed.

2. Install Cilium with [`cilium-values.yaml`](cilium-values.yaml):

   ```sh
   helm repo add cilium https://helm.cilium.io
   helm upgrade --install cilium cilium/cilium --version 1.20.4 \
     --namespace kube-system -f cilium-values.yaml
   ```

   The values pin every Cilium component to the node group. Check these before you install:
   - `operator.unmanagedPodWatcher.restart: false`. The default restarts every Pod that Cilium does not manage, so with Cilium on some nodes only, it restarts Pods on all other nodes.
   - `ipam.operator.clusterPoolIPv4PodCIDRList`. Cilium uses it only for its own router address on each node. Use a range that does not overlap the VPC or the service CIDR.

3. Check that Cilium is ready and that nothing else changed:

   ```sh
   kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief
   kubectl get pods -A -o wide | grep cilium
   ```

   Every Cilium Pod must be on the Cilium nodes.

Do not add Kubernetes NetworkPolicies to the workspace namespace. VPC CNI enforces them on every node, also on top of Cilium.

## 2. Apply

Run Terraform from this directory with an account that can create namespaces, RBAC, and Cilium policies:

```sh
terraform init
terraform apply -var namespace=coder-workspaces
```

Set `namespace` to the namespace for workspaces, and use the same value in the template. If the namespace exists already, set `create_namespace = false`. If the Coder provisioner does not run as the `coder` ServiceAccount in the `coder` namespace, set `provisioner_service_account`.

Keep the Terraform state. Terraform needs it to change or remove the setup later.

## Kernel isolation

To offer gVisor or Kata, install them on the Cilium nodes with a RuntimeClass named `gvisor`, `kata-qemu`, or `kata-clh`, and list them in the template's `runtimes` variable. See [Install the runtimes](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-agent-sandbox/cluster/README.md#2-install-the-runtimes) in the agent-sandbox template.

## Removal

- Delete the workspaces and the template first.
- Changing `create_namespace` from `true` to `false` deletes the namespace and every workspace in it. To stop managing an existing namespace, run `terraform state rm 'kubernetes_namespace_v1.workspaces[0]'` first.
- `terraform destroy` removes everything this configuration created, including the namespace if it created it.
- To remove Cilium from a node group, run `helm uninstall cilium --namespace kube-system`, delete the CRDs in `cilium.io`, and delete the node group. Replace its nodes, because Cilium leaves its CNI config on them.
