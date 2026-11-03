# Cluster setup for kubernetes-agent-sandbox

A cluster administrator sets up the cluster once. The Terraform configuration in this directory creates everything the template needs in the cluster:

- The workspace namespace, and a Role and RoleBinding for the Coder provisioner. The provisioner can manage workspaces in this namespace only. It can read the SandboxTemplates and warm pools, but cannot change them.
- A ClusterRole that lets the provisioner read CRDs, which `kubernetes_manifest` needs at plan time.
- One SandboxTemplate and one SandboxWarmPool for each runtime and scratch profile, for scratch homes.
- Optionally, a cluster-wide guardrail on Amazon EKS.

Persistent homes need only the namespace and the Role. The template creates their Sandbox, disk, and NetworkPolicy.

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

The template supports three RuntimeClasses: `gvisor`, `kata-qemu`, and `kata-clh`. Install the ones you want to offer, and list them in `runtimes` in step 3.

### gVisor

gVisor runs on any Linux node. Install `runsc` and its containerd shim on each node, add a `runsc` runtime to the containerd config, and create a RuntimeClass named `gvisor` with `handler: runsc`. See the [gVisor containerd guide](https://gvisor.dev/docs/user_guide/containerd/quick_start/). On GKE, GKE Sandbox provides the `gvisor` RuntimeClass.

Use `release-20261019.0` or later. Older releases block when the Coder agent writes nothing to a terminal, which it does on every resize, so the web terminal takes no input. To check the version on a node, run `runsc --version`. Sandboxes that are already running keep their version until they restart.

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

## 3. Set your values

Copy [`example.tfvars`](example.tfvars) to `install.auto.tfvars` in this directory and edit it. Terraform loads `*.auto.tfvars` files on its own, and `coder templates push` leaves them out of the template.

| Variable                      | Default                  | Description                                                                                                    |
| ----------------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------- |
| `namespace`                   | none                     | The namespace for workspaces.                                                                                  |
| `workspace_image`             | none                     | The image built from `build/Dockerfile`, with a fixed tag or a digest.                                         |
| `coder_access_url`            | none                     | The Coder access URL, for example `https://coder.example.com`.                                                 |
| `coder_egress_cidrs`          | none                     | The IPv4 CIDR ranges of the Coder server, for example `["203.0.113.10/32"]`.                                   |
| `coder_egress_port`           | from the URL             | The TCP port to the Coder server. Empty uses the port of `coder_access_url`, or 443 for https and 80 for http. |
| `coder_host_ip`               | `""`                     | The Coder server IP. Set it if `coder_access_url` uses a host name, because Fully isolated blocks DNS.         |
| `runtimes`                    | `["gvisor"]`             | The runtimes to create pools for: `gvisor`, `kata-qemu`, `kata-clh`.                                           |
| `scratch_profiles`            | `["isolated", "github"]` | The network profiles to create pools for. `[]` creates no pools.                                               |
| `warm_pool_replicas`          | `1`                      | Idle sandboxes in each pool. See [Size the warm pools](#size-the-warm-pools).                                  |
| `git_repo_url`                | `""`                     | A public repository that GitHub only pools clone while they wait.                                              |
| `network_policy_gate`         | `true`                   | Start the agent only once the NetworkPolicy blocks the Kubernetes API server.                                  |
| `enable_guardrail`            | `false`                  | Create the cluster-wide guardrail. Amazon EKS only. See [Guardrail](#guardrail).                               |
| `create_namespace`            | `true`                   | Create the namespace. Set `false` if it exists.                                                                |
| `provisioner_service_account` | `coder` in `coder`       | The ServiceAccount of the Coder provisioner.                                                                   |
| `grant_crd_read`              | `true`                   | Let the provisioner read CRDs.                                                                                 |
| `kubeconfig_path`             | `~/.kube/config`         | The kubeconfig file.                                                                                           |
| `kubeconfig_context`          | `""`                     | The kubeconfig context. Empty uses the current context.                                                        |

## 4. Apply

Run Terraform from this directory with an account that can create namespaces, RBAC, and agent-sandbox resources:

```sh
terraform init
terraform apply
```

Install agent-sandbox (step 1) first. Terraform reads the agent-sandbox CRDs when it plans, so the plan fails without them. The guardrail also needs the ClusterNetworkPolicy CRD, which VPC CNI v1.21.1 or later installs.

Keep the Terraform state. Terraform needs it to change or remove the setup later. If more than one person runs it, use a [remote backend](https://developer.hashicorp.com/terraform/language/backend).

Check that each pool has a ready sandbox:

```sh
kubectl get sandboxwarmpool -n <namespace>
```

The GitHub only pools turn ready after their Pods clone the repository, about 40 s for coder/coder.

## 5. Push the template with the same values

The template and the pools must agree on the namespace, image, Coder address, runtimes, and scratch profiles. The `coder_variables` output has these as a variables file for `coder templates push`. Write it outside the template directory:

```sh
terraform output -raw coder_variables > ~/kubernetes-agent-sandbox.yaml
cd ..
coder templates push kubernetes-agent-sandbox -d . --variables-file ~/kubernetes-agent-sandbox.yaml
```

Add other template variables, such as `prebuild_instances`, to the file. The template takes `runtimes` and `scratch_profiles` comma-separated, for example `gvisor,kata-clh`, because Coder checks presets with every variable as a string. The output already has them in that form. Run both steps again when you change a value.

## Changes and removal

- A change to the image, the Coder address, the network rules, or `git_repo_url` changes the SandboxTemplates. The pools use `updateStrategy.type: Recreate`, so they replace their idle sandboxes. Claimed sandboxes keep running until their workspace stops.
- Removing a runtime or a profile from the lists deletes its SandboxTemplate and pool. Remove it from the template first, so that no new workspace claims from it.
- Changing `create_namespace` from `true` to `false` deletes the namespace and every workspace in it. To stop managing an existing namespace, run `terraform state rm 'kubernetes_namespace_v1.workspaces[0]'` first.
- `terraform destroy` removes everything this configuration created, including the namespace if it created it.

## Size the warm pools

Each pool keeps `warm_pool_replicas` booted, idle sandboxes. A scratch workspace claims one and is ready in about 3.5 to 6.5 s, and the pool boots a replacement. Set it to the number of scratch workspaces that start at about the same time. With `0`, a scratch workspace waits until the pool boots a sandbox, so remove the profile from `scratch_profiles` instead if you do not want scratch homes.

Each idle sandbox reserves the Pod's requests (500m CPU and 1 GiB) plus the RuntimeClass overhead (Kata: 250m CPU and 130 to 320 MiB). In our test cluster, one idle sandbox filled a 2 CPU, 4 GiB slot on an `m7i.2xlarge` node: about $0.058 an hour, or $42 a month, at us-east-1 on-demand prices. An idle sandbox also uses a little CPU for the runtime and for the loop that waits for the token. Use `kubectl top pod` to see it on your nodes.

## How a pooled sandbox starts

1. The Pod boots and copies the image's dotfiles into `/home/coder`. A GitHub only Pod then clones `git_repo_url`. The Pod turns ready after this.
2. It waits for the file `/podinfo/token`.
3. A workspace build creates a SandboxClaim. agent-sandbox hands it an idle Pod and adds the claim's annotations to the Pod.
4. The downward API writes the `coder.com/agent-token` annotation to `/podinfo/token`, usually within a second.
5. The Pod runs [`../shared/start-agent.sh`](../shared/start-agent.sh). It waits until a TCP connection to the Kubernetes API server fails, which shows that its NetworkPolicy is in force, and then starts the Coder agent as PID 1. Every 5 s it checks again. If the API server becomes reachable, it stops the agent and the container exits.

Persistent homes run the same script, so the two cannot drift apart. The GitHub ranges, DNS servers, private ranges, and Pod resources come from [`../shared/defaults.json`](../shared/defaults.json), which both use too.

The agent token stays in plain text in the Pod annotation and the SandboxClaim, so only trusted users should read Pods and SandboxClaims in the namespace.

Claimed Pods get only annotations, not the `com.coder.workspace.id` label, because claim labels need a domain from the controller's `allowed-label-domains` setting.

## Network rules of the pools

Each SandboxTemplate sets its own NetworkPolicy, which replaces the agent-sandbox default:

- `coder-<runtime>`: Fully isolated, the Coder server only.
- `coder-<runtime>-github`: GitHub only, the Coder server, the GitHub ranges, and DNS to `8.8.8.8` and `1.1.1.1`.

Pods of one pool share one NetworkPolicy. On Amazon VPC CNI, the Pods of one pool on one node also share their network rules, so each network profile has its own pool, and Public internet has no scratch home.

## Guardrail

The NetworkPolicies of the template and the SandboxTemplates are namespace-scoped. Anyone who can edit a SandboxTemplate or create a NetworkPolicy in the namespace can open the network.

With `enable_guardrail = true`, Terraform adds a ClusterNetworkPolicy in the Admin tier, which Amazon EKS checks before every NetworkPolicy. For every Pod in the workspace namespace, it allows the Coder server, and it blocks private, shared, and link-local ranges (the VPC, other Pods, the Kubernetes API server, and cloud metadata) and ingress from other Pods. The rest goes on to the NetworkPolicies, so the profiles work as before. It needs VPC CNI v1.21.1 or later. On other clusters, the upstream [Network Policy API](https://network-policy-api.sigs.k8s.io/) `ClusterNetworkPolicy` can do the same, but it has another API group and schema.

In our test, a new Pod got the guardrail about 2 s after it started, the same as a NetworkPolicy. So keep `network_policy_gate` on. The ingress rule becomes a list of Pod IP addresses, so a Pod that started a few seconds ago can still connect until the list catches up. The profiles' own NetworkPolicies block all ingress too.

The guardrail and the profiles match IP ranges. To allow host names, such as `registry.npmjs.org`, you need a network plugin with DNS-based rules, such as [Cilium `toFQDNs`](https://docs.cilium.io/en/stable/security/dns/) or EKS Auto Mode `ApplicationNetworkPolicy`, or an egress proxy that checks the host name. A rule based on DNS still allows every host behind an allowed IP address. Only a proxy can tell hosts on a shared IP address apart.
