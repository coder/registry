---
display_name: OpenShell (Kubernetes)
description: Run each workspace in an NVIDIA OpenShell sandbox, with a firewall by host name and program
icon: ../../../../.icons/openshell.svg
verified: false
tags: [kubernetes, openshell, sandbox, firewall, kata, ai]
---

# OpenShell (Kubernetes)

Run each workspace in an [NVIDIA OpenShell](https://docs.nvidia.com/openshell/latest/about/overview) sandbox. You and your AI agent work in the same sandbox, with one Coder agent named `dev`. OpenShell blocks all network access by default. Its proxy checks each connection against a policy that names the host and the program that opens it. It also limits file access with Landlock. By default the workspace can reach only the Coder server.

## Why OpenShell

- **Rules for each program:** a rule can let `git` reach `github.com` and still block `python3` from the same host. OpenShell logs each denied connection with the program name.
- **Rules you can change live:** `openshell policy update` opens a host for a running sandbox, with no restart.
- **File limits:** Landlock makes `/usr` and `/etc` read-only and denies every path that is not in the policy, such as `/home` and `/root`, even to code that runs as the workspace user.
- **Kernel isolation:** with Kata, each sandbox is a microVM with its own kernel.

If host names are enough, use [Plain Sandbox (Kubernetes)](https://registry.coder.com/templates/coder-labs/kubernetes-sandboxed). It has fewer parts and faster stops. OpenShell is at version 0.1, so pin the version and test each upgrade.

## Startup speed

With a prebuild, workspaces often start in about 2 seconds, which matters for agents that start a new workspace for each task. To see where the time goes, see [Speed tuning](#speed-tuning).

## Prerequisites

Required:

- **A Kubernetes cluster** with a network plugin that enforces NetworkPolicy, a StorageClass for the home disk, and Linux 6.2 or later on the nodes, for Landlock.
- **[agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)** v1.0.4 or later, which the OpenShell Kubernetes driver uses.
- **The cluster setup** in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster): a Terraform configuration that installs the OpenShell gateway and creates the namespace, the RBAC, and the gateway credentials. See [`cluster/README.md`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster/README.md).
- **The workspace image**, built from [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/build/Dockerfile).
- **The launcher image**, built from [`build/launcher/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/build/launcher/Dockerfile). It has only the `openshell` CLI.
- **Access to the cluster** for the Coder provisioner. The template uses the in-cluster ServiceAccount, or `~/.kube/config` with `use_kubeconfig = true`. With the AI Gateway on, the provisioner also calls the Coder API at the access URL to create the workspace's token.

Optional:

- **Kata nodes**, for a microVM for each workspace: a node group with `/dev/kvm`. List them in `runtimes`. gVisor does not work, because it has no Landlock.
- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.
- **A DaemonSet that pulls the image** on every node.

## Quick start

1. Build both images and push them to your registry. See [Build the images](#build-the-images).
2. Install agent-sandbox, and set up the cluster with the Terraform configuration in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster).
3. Write the variables that `cluster/` prints to a file outside the template directory, add the images, and push the template:

   ```sh
   cd cluster
   terraform output -raw coder_variables > ~/kubernetes-openshell.yaml
   cd ..
   cat >> ~/kubernetes-openshell.yaml << 'EOF'
   workspace_image: registry.example.com/coder/workspace:v2.30.0
   launcher_image: registry.example.com/coder/openshell-launcher:0.1.5
   EOF
   coder templates push kubernetes-openshell -d . --variables-file ~/kubernetes-openshell.yaml
   ```

Users pick the network profile and, if you set `runtimes`, the runtime when they create a workspace. They cannot change them later. Each profile except Custom is a preset with `prebuild_instances` prebuilds on the node's container runtime.

## Build the images

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_VERSION=2.30.0 \
  -t registry.example.com/coder/workspace:v2.30.0 --push build
docker buildx build --platform linux/amd64 \
  --build-arg OPENSHELL_VERSION=0.1.5 \
  -t registry.example.com/coder/openshell-launcher:0.1.5 --push build/launcher
```

- Match `CODER_VERSION` to your Coder server, and `OPENSHELL_VERSION` to your gateway. Rebuild when you upgrade either. `CODER_BINARY_URL`, such as `https://coder.example.com/bin/coder-linux-amd64`, copies the binary from your server instead of GitHub.
- `INSTALL_CODE_SERVER=false` and `INSTALL_CLAUDE_CODE=false` leave out the tools. With `INSTALL_CLAUDE_CODE=false`, set `enable_claude_code = false` in the template.
- Use a fixed tag or a digest. The template rejects `:latest`, because with `imagePullPolicy: IfNotPresent` the nodes keep an old copy.

## Architecture

Terraform cannot call the OpenShell gateway, so a small launcher Pod does it:

1. **Start:** Terraform creates the home disk, a Secret with the agent token, and the launcher Pod. The launcher runs `openshell sandbox create` with the profile's policy, and the Coder agent is the main process of the sandbox.
2. **Sandbox:** the gateway creates an agent-sandbox Sandbox, a supervisor Pod, and NetworkPolicies. The sandbox can talk only to its supervisor, so traffic cannot go around the proxy.
3. **Stop:** Kubernetes stops the launcher, and the launcher deletes the sandbox. The home disk stays.

- **Home:** Coder owns the disk, which is mounted at `/sandbox/home`. Files there survive a stop.
- **Pods:** the sandbox runs as user 1000. OpenShell sets `cpu` and `memory` (1 CPU and 2 GiB by default) as both the request and the limit.
- **Apps:** code-server, and Claude Code, which continues the last conversation in `/sandbox/home`.

## Speed tuning

In our Amazon EKS test cluster (`m7i.2xlarge` nodes, VPC CNI), from create to a connected agent:

| Workspace                            | Ready in   |
| ------------------------------------ | ---------- |
| From a prebuild                      | about 2 s  |
| No prebuild, Custom                  | about 14 s |
| No prebuild, Kata (Cloud Hypervisor) | about 17 s |
| Start after stop                     | about 24 s |
| Stop                                 | about 37 s |

These all add to the speed:

1. **Prebuilds** (Premium). A claim changes no Pod, so the sandbox keeps running, and the build takes about 1.5 s. GitHub profiles have already cloned `git_repo_url`.
2. **The image.** [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/build/Dockerfile) adds the Coder agent, code-server, and Claude Code, so a start downloads nothing, and it also works in Fully isolated. The image is about 800 MB compressed, so pull it ahead of time with a DaemonSet.
3. **The disks and the supervisor.** A cold start waits for the home disk to attach and for the supervisor Pod. Stop waits until OpenShell deletes the sandbox.
4. **Free CPU.** OpenShell reserves the full `cpu` for each sandbox, so a full cluster leaves new sandboxes Pending. Lower `cpu`, or add nodes.

## Firewall

The OpenShell proxy is the firewall. It runs in the supervisor, outside the workspace, so code in the workspace cannot change it. Each rule names a host, a port, and the programs that can use them. Everything else is denied and logged.

- **Coder:** the Coder agent and Claude Code can reach the access URL, and so can every program they start, such as the shells in your terminal.
- **Profile hosts:** every program can reach them.

To open a host for a running workspace only:

```sh
openshell policy update "$SANDBOX" --rule-name extra \
  --binary /usr/bin/curl --add-endpoint example.com:443 --wait
```

`$SANDBOX` is the sandbox name: `coder-` and the first 13 characters of the workspace ID without dashes. The change is gone after the next stop. To see blocked requests, run `openshell logs "$SANDBOX" --since 5m --source sandbox`.

### Network ingress

The sandbox accepts connections only from its supervisor. The Coder agent dials out to the Coder server, so the web terminal, code-server, `coder ssh`, port forwarding, and desktop IDEs all relay through Coder.

### Network egress

| Profile                       | Can reach, in addition to Coder                                     |
| ----------------------------- | ------------------------------------------------------------------- |
| Fully isolated (default)      | Nothing                                                             |
| GitHub only                   | GitHub host names on 443                                            |
| GitHub and package registries | GitHub, npm, the Go module proxy, and PyPI on 443                   |
| Custom                        | The host names and ports that you type. No preset, so a cold start. |

There is no Public internet profile, because OpenShell 0.1.5 has no rule for any public host. With Custom, the form shows a list of host names and a choice of ports 443, 80, and 22. `*.example.com` matches one label, such as `api.example.com`, and `**.example.com` matches any depth. Neither matches `example.com` itself, so add it too if you need it. The form rejects IP addresses, names without a dot, `*.com`, and cluster names such as `.svc` or `.local`, and the build checks them again.

## Limits

- OpenShell decrypts HTTPS by default. It adds its own CA through `SSL_CERT_FILE` and similar variables, so it can read the traffic it allows.
- The launcher uses the gateway's client certificate, which can manage every sandbox. Anyone who can read Secrets in the namespace can use it. Use OIDC in production.
- OpenShell puts the agent token in plain text in the sandbox Pod and its Sandbox, so keep read access to the namespace tight.
- If the launcher container exits, Kubernetes restarts it, and it replaces the sandbox. The home stays, but running programs stop.
- Without Kata, the sandbox shares the node kernel, with Landlock and seccomp only.
- An allowed host that stores user content, such as GitHub, can receive data from the workspace.
- With the AI Gateway on, each start gives the workspace a new Coder token with only the `user:read_personal` scope, which the AI Gateway accepts. Code in the workspace can use it for AI requests. Coder cannot revoke it on stop, so it stays valid until the default token lifetime ends, and it shows in the owner's token list as `ai-gateway-<workspace>-<time>`.
- No root, no Docker, IPv4 only.
