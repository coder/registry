# Cluster setup for kubernetes-agent-sandbox

A cluster administrator applies the files in this directory once per cluster. The template uses them, but Terraform does not create them.

| File                                                         | Needed for           | What it creates                                                                  |
| ------------------------------------------------------------ | -------------------- | -------------------------------------------------------------------------------- |
| [`rbac.yaml`](rbac.yaml)                                     | Every workspace      | The workspace namespace, and a Role and RoleBinding for the Coder provisioner    |
| [`sandbox-templates.yaml`](sandbox-templates.yaml)           | Scratch homes        | One SandboxTemplate per runtime (Fully isolated), and one for gVisor GitHub only |
| [`warm-pools.yaml`](warm-pools.yaml)                         | Scratch homes        | One SandboxWarmPool for each SandboxTemplate                                     |
| [`cluster-network-policy.yaml`](cluster-network-policy.yaml) | Optional, Amazon EKS | A cluster-wide guardrail that no NetworkPolicy can undo                          |

Persistent homes need only `rbac.yaml`. Terraform creates their Sandbox, disk, and NetworkPolicy.

## 1. Install agent-sandbox

Install the controller and the extensions, v1.0.4 or later. The extensions add SandboxTemplate, SandboxClaim, and SandboxWarmPool:

```sh
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.4/sandbox-with-extensions.yaml
```

The default settings suit one warm pool. With more pools, add these flags to the controller Deployment, so that the pools refill at the same time:

```sh
kubectl -n agent-sandbox-system patch deployment agent-sandbox-controller --type json -p '[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--sandbox-warm-pool-concurrent-workers=4"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--api-connections=4"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--separate-watch-connection=true"}
]'
```

Set `--sandbox-warm-pool-concurrent-workers` to the number of pools. These flags make refills faster. Claims were already fast, 50 to 80 ms. The template puts only annotations on a claimed Pod, so you do not need to change the `allowed-label-domains` setting. See the agent-sandbox `docs/performance-tuning.md` for all flags.

## 2. Install the runtimes

The template offers three RuntimeClasses: `gvisor`, `kata-qemu`, and `kata-clh`. Install the ones you offer.

### gVisor

gVisor runs on any Linux node. Install `runsc` and its containerd shim on each node, add a `runsc` runtime to the containerd config, and create a RuntimeClass named `gvisor` with `handler: runsc`. See the [gVisor containerd guide](https://gvisor.dev/docs/user_guide/containerd/quick_start/). On GKE, GKE Sandbox provides the `gvisor` RuntimeClass.

### Kata (QEMU and Cloud Hypervisor)

Kata runs each Pod in a small VM, so the node needs `/dev/kvm`: a bare metal node, or a VM with nested virtualization.

On EC2, C7i, M7i, R7i, C8i, M8i, and R8i instances support nested virtualization when they start with `CpuOptions.NestedVirtualization=enabled`. eksctl cannot set this, so create the node group from an EC2 launch template, and label its nodes `coder.com/runtime=kata`.

Install Kata with the [kata-deploy Helm chart](https://github.com/kata-containers/kata-containers/blob/main/tools/packaging/kata-deploy/helm-chart/README.md). With these values, it installs only the QEMU and Cloud Hypervisor shims, and only on the Kata nodes:

```yaml
# kata-values.yaml
nodeSelector:
  coder.com/runtime: kata
shims:
  disableAll: true
  qemu:
    enabled: true
  clh:
    enabled: true
runtimeClasses:
  enabled: true
  createDefault: false
```

```sh
helm install kata-deploy oci://ghcr.io/kata-containers/kata-deploy-charts/kata-deploy \
  --version 4.2.0 -n kube-system -f kata-values.yaml
```

The `kata-qemu` and `kata-clh` RuntimeClasses from the chart have a `scheduling.nodeSelector`, so Kubernetes places Kata Pods on the Kata nodes without a nodeSelector in the template.

Cloud Hypervisor starts faster. QEMU is the more common choice and supports more devices. On a cold start, gVisor added about 0.2 s over a normal container, Cloud Hypervisor about 1.5 s, and QEMU about 2.6 s. A warm pool or a prebuild hides this time.

To check a runtime, start a Pod with it and look at the kernel. gVisor reports a kernel such as `4.4.0` or `4.19.0-gvisor`, and Kata reports the VM kernel, not the node kernel:

```sh
kubectl run kata-check --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"runtimeClassName":"kata-clh"}}' -- uname -r
```

## 3. Replace the example values

The files use example values. Replace them in every file:

| Example value                                  | Replace with                                 | Files                                                   |
| ---------------------------------------------- | -------------------------------------------- | ------------------------------------------------------- |
| `coder-workspaces`                             | Your namespace, the `namespace` variable     | All                                                     |
| `registry.example.com/coder/workspace:v2.30.0` | Your `workspace_image`                       | `sandbox-templates.yaml`                                |
| `https://coder.example.com`                    | Your Coder access URL                        | `sandbox-templates.yaml`                                |
| `203.0.113.10/32` and `port: 443`              | `coder_egress_cidrs` and `coder_egress_port` | `sandbox-templates.yaml`, `cluster-network-policy.yaml` |
| `https://github.com/coder/coder`               | Your `git_repo_url`, a public repository     | `sandbox-templates.yaml` (`coder-gvisor-github`)        |
| `coder` in namespace `coder`                   | The Coder provisioner ServiceAccount         | `rbac.yaml`                                             |

```sh
sed -i \
  -e 's/coder-workspaces/<namespace>/g' \
  -e 's#registry.example.com/coder/workspace:v2.30.0#<workspace_image>#g' \
  -e 's#https://coder.example.com#<access URL>#g' \
  -e 's#203.0.113.10/32#<Coder server CIDR>#g' \
  -e 's/port: 443$/port: <Coder port>/' \
  -e 's#https://github.com/coder/coder#<git_repo_url>#g' \
  *.yaml
```

If the access URL uses a host name, Fully isolated cannot resolve it, because it blocks DNS. Uncomment `hostAliases` in the Fully isolated SandboxTemplates and set the Coder server IP.

## 4. Apply the files

```sh
kubectl apply -f rbac.yaml -f sandbox-templates.yaml -f warm-pools.yaml
# Optional, on Amazon EKS:
kubectl apply -f cluster-network-policy.yaml
```

Check that each pool has a ready sandbox:

```sh
kubectl get sandboxwarmpool -n <namespace>
```

The GitHub only pool turns ready after its Pod clones the repository, about 40 s for coder/coder.

If a build fails with `customresourcedefinitions ... is forbidden`, the provisioner also needs to read CRDs, because `kubernetes_manifest` reads the Sandbox and SandboxClaim CRDs at plan time. CRDs are cluster-scoped, so a Role cannot grant this:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: coder-crd-read
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: coder-crd-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: coder-crd-read
subjects:
  - kind: ServiceAccount
    name: coder
    namespace: coder
```

## Size the warm pools

Each pool keeps `replicas` booted, idle sandboxes (1 in the example). A scratch workspace claims one and is ready in about 3.5 to 6.5 s, and the pool boots a replacement. Set `replicas` to the number of scratch workspaces that start at about the same time, and to 0 for a runtime you do not offer.

Each idle sandbox reserves the Pod's requests (500m CPU and 1 GiB) plus the RuntimeClass overhead (Kata: 250m CPU and 130 to 320 MiB). In our test cluster, one idle sandbox filled a 2 CPU, 4 GiB slot on an `m7i.2xlarge` node: about $0.058 an hour, or $42 a month, at us-east-1 on-demand prices. An idle sandbox also uses a little CPU for the runtime and for the loop that waits for the token. Use `kubectl top pod` to see it on your nodes.

The pools use `updateStrategy.type: Recreate`, so they replace idle sandboxes when you change a SandboxTemplate. The default, `OnReplenish`, keeps old idle sandboxes until someone claims them.

## How a pooled sandbox starts

1. The Pod boots and copies the image's dotfiles into `/home/coder`. A GitHub only Pod then clones the repository.
2. It waits for the file `/podinfo/token`.
3. A workspace build creates a SandboxClaim. agent-sandbox hands it an idle Pod and adds the claim's annotations to the Pod.
4. The downward API writes the `coder.com/agent-token` annotation to `/podinfo/token`, usually within a second.
5. The Pod waits until a TCP connection to the Kubernetes API server fails, which shows that its NetworkPolicy is in force. Then it starts the Coder agent as PID 1. Every 5 s it checks again. If the API server becomes reachable, it stops the agent and the container exits.

The agent token stays in plain text in the Pod annotation and the SandboxClaim, so only trusted users should read Pods and SandboxClaims in the namespace.

Claimed Pods get only annotations, not the `com.coder.workspace.id` label, because claim labels need a domain from the controller's `allowed-label-domains` setting.

The start script in the SandboxTemplates must match `policy_check` in `main.tf`. If you change one, change the other.

## Network rules of the pools

Each SandboxTemplate sets its own NetworkPolicy, which replaces the agent-sandbox default:

- `coder-gvisor`, `coder-kata-qemu`, and `coder-kata-clh`: Fully isolated, the Coder server only.
- `coder-gvisor-github`: GitHub only, the Coder server, the GitHub ranges from `local.github_cidrs` in `main.tf`, and DNS to `8.8.8.8` and `1.1.1.1`.

Pods of one pool share one NetworkPolicy. On Amazon VPC CNI, the Pods of one pool on one node also share their network rules, so each network profile needs its own pool, and Public internet has no scratch home. To offer GitHub only on Kata, copy the `coder-gvisor-github` block and its warm pool, and change the name and `runtimeClassName`.

## Guardrail

The NetworkPolicies of the template and the SandboxTemplates are namespace-scoped. Anyone who can edit a SandboxTemplate or create a NetworkPolicy in the namespace can open the network.

[`cluster-network-policy.yaml`](cluster-network-policy.yaml) is a ClusterNetworkPolicy in the Admin tier, which Amazon EKS checks before every NetworkPolicy. For every Pod in the workspace namespace, it allows the Coder server, and it blocks private, shared, and link-local ranges (the VPC, other Pods, the Kubernetes API server, and cloud metadata) and ingress from other Pods. The rest goes on to the NetworkPolicies, so the profiles work as before. It needs VPC CNI v1.21.1 or later. On other clusters, the upstream [Network Policy API](https://network-policy-api.sigs.k8s.io/) `ClusterNetworkPolicy` can do the same, but it has another API group and schema, so the file needs changes.

In our test, a new Pod got the guardrail about 2 s after it started, the same as a NetworkPolicy. So keep `network_policy_gate` on. The ingress rule becomes a list of Pod IP addresses, so a Pod that started a few seconds ago can still connect until the list catches up. The profiles' own NetworkPolicies block all ingress too.

The guardrail and the profiles match IP ranges. To allow host names, such as `registry.npmjs.org`, you need a network plugin with DNS-based rules, such as Cilium `toFQDNs` or EKS Auto Mode `ApplicationNetworkPolicy`, or an egress proxy that checks the host name. A rule based on DNS still allows every host behind an allowed IP address. Only a proxy can tell hosts on a shared IP address apart.
