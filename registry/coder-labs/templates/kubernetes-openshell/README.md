---
display_name: OpenShell (Kubernetes)
description: Run each workspace in an NVIDIA OpenShell sandbox in a Kata microVM, with a firewall by host name and program
icon: ../../../../.icons/openshell.svg
verified: false
tags: [kubernetes, openshell, sandbox, firewall, kata, ai]
---

# OpenShell (Kubernetes)

Run each workspace in an [NVIDIA OpenShell](https://docs.nvidia.com/openshell/latest/about/overview) sandbox. You and your AI agent work in the same sandbox, with one Coder agent named `dev`. OpenShell blocks all network access by default. Its proxy checks each connection against a policy that names the host and the program that opens it. It also limits file access with Landlock. By default the workspace can reach only the Coder server.

Each workspace Pod is one Kata microVM that runs its own OpenShell gateway and Docker daemon. There is no shared gateway, no controller, and no Helm chart to install.

## Why OpenShell

- **Rules for each program:** a rule can let `git` reach `github.com` and still block `python3` from the same host. OpenShell logs each denied connection with the program name.
- **Rules you can change live:** `openshell policy update` opens a host for a running sandbox, with no restart.
- **File limits:** Landlock makes `/usr` and `/etc` read-only and denies every path that is not in the policy, even to code that runs as the workspace user.
- **Kernel isolation:** each workspace is a microVM with its own kernel.

If host names are enough, use [Plain Sandbox (Kubernetes)](https://registry.coder.com/templates/coder-labs/kubernetes-sandboxed). It has fewer parts, needs no Kata, and starts faster without a prebuild. OpenShell is at version 0.1, so pin the version and test each upgrade.

## Startup speed

With a prebuild, workspaces often start in about 2 seconds, which matters for agents that start a new workspace for each task. To see where the time goes, see [Speed tuning](#speed-tuning).

## Prerequisites

Required:

- **A Kubernetes cluster** with a network plugin that enforces NetworkPolicy, and a StorageClass with `volumeMode: Block`, such as EBS.
- **Kata nodes:** a node group with `/dev/kvm` and the `kata-clh` or `kata-qemu` RuntimeClass. The Docker daemon is privileged inside the VM, so the template does not run without Kata. See [Install the runtimes](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-agent-sandbox/cluster/README.md#2-install-the-runtimes) in the agent-sandbox template.
- **A Coder agent with `CODER_AGENT_DERP_ONLY`:** the sandbox has only loopback, so the agent must connect through the Coder DERP relay. This option is not in a Coder release yet.
- **The cluster setup** in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster): a Terraform configuration that creates the namespace and the RBAC. See [`cluster/README.md`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster/README.md).
- **The workspace image**, built from [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/build/Dockerfile).
- **The launcher image**, built from [`build/launcher/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/build/launcher/Dockerfile). It has the OpenShell gateway, the `openshell` CLI, and the Docker CLI.
- **Access to the cluster** for the Coder provisioner. The template uses the in-cluster ServiceAccount, or `~/.kube/config` with `use_kubeconfig = true`. With the AI Gateway on, the provisioner also calls the Coder API at the access URL to create the workspace's token.

Optional:

- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.
- **A registry close to the cluster**, because each new workspace pulls the image into its own Docker daemon.

## Quick start

1. Build both images and push them to your registry. See [Build the images](#build-the-images).
2. Set up the cluster with the Terraform configuration in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-openshell/cluster).
3. Write the template variables to a file outside the template directory, and push the template:

   ```sh
   cat > ~/kubernetes-openshell.yaml << 'EOF'
   namespace: coder-workspaces
   workspace_image: registry.example.com/coder/workspace:v2.30.0
   launcher_image: registry.example.com/coder/openshell-launcher:0.1.5
   runtimes: kata-clh
   EOF
   coder templates push kubernetes-openshell -d . --variables-file ~/kubernetes-openshell.yaml
   ```

Users pick the network profile and the runtime when they create a workspace. They cannot change them later. Each profile except Custom is a preset with `prebuild_instances` prebuilds on the first runtime in `runtimes`.

If the image is private, create a `kubernetes.io/dockerconfigjson` Secret in the namespace and set `image_pull_secret`. If the Coder server has a private address, set `coder_egress_cidrs`, because the NetworkPolicy blocks private ranges.

## Build the images

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_VERSION=2.30.0 \
  -t registry.example.com/coder/workspace:v2.30.0 --push build
docker buildx build --platform linux/amd64 \
  --build-arg OPENSHELL_VERSION=0.1.5 \
  -t registry.example.com/coder/openshell-launcher:0.1.5 --push build/launcher
```

- Match `CODER_VERSION` to your Coder server, and rebuild when you upgrade Coder. `CODER_BINARY_URL`, such as `https://coder.example.com/bin/coder-linux-amd64`, copies the binary from your server instead of GitHub.
- `INSTALL_CODE_SERVER=false` and `INSTALL_CLAUDE_CODE=false` leave out the tools. With `INSTALL_CLAUDE_CODE=false`, set `enable_claude_code = false` in the template.
- Use a fixed tag or a digest. The template rejects `:latest`, because the Docker daemon in the Pod keeps an old copy.

## Architecture

Terraform creates one Pod for each started workspace, with two containers in one Kata VM:

1. **docker:** a Docker daemon, privileged inside the VM only. Its data is on the workspace's Docker disk, a raw block device that it formats with ext4.
2. **launcher:** starts an OpenShell gateway on loopback with mTLS, then runs `openshell sandbox create`. The gateway's Docker driver runs the sandbox and its supervisor as Docker containers. The Coder agent is the main process of the sandbox.

- **For the life of the workspace:** the Docker disk and the NetworkPolicy. The disk keeps the home, the image, and the gateway's images.
- **While started:** a Secret with the agent token, and the Pod. Stop deletes them and keeps the disk.
- **Home:** a Docker volume on the Docker disk, mounted at `/home/coder`. Files there survive a stop. Everything else in the sandbox is reset on each start.
- **Policy check:** before the gateway starts, the launcher waits until the Kubernetes API server is unreachable, which shows that the NetworkPolicy is in force. It checks again every 5 s and deletes the sandbox if the API server becomes reachable.
- **Apps:** code-server, and Claude Code, which continues the last conversation in `/home/coder`.

## Speed tuning

In our Amazon EKS test cluster (`m7i.2xlarge` nodes, VPC CNI, Kata Cloud Hypervisor), from create to a connected agent:

| Workspace           | Ready in   |
| ------------------- | ---------- |
| From a prebuild     | about 2 s  |
| Start after stop    | about 17 s |
| No prebuild, Custom | about 85 s |
| Stop                | about 5 s  |

These all add to the speed:

1. **Prebuilds** (Premium). A claim changes no Pod, so the sandbox keeps running, and the build takes about 1.5 s. GitHub profiles have already cloned `git_repo_url`.
2. **The image pull.** A new workspace has an empty Docker disk, so the Docker daemon pulls the image first. That is about 65 s of the 85 s for an 800 MB image. A start after stop finds the image on the disk. A smaller image or a registry close to the cluster helps.
3. **The disk and the VM.** A start waits for the EBS volume to attach and for the Kata VM to boot, about 10 s.
4. **Free CPU.** The Kata RuntimeClass adds overhead to each Pod, so a full node group leaves new workspaces Pending.

## Firewall

There are two layers, so a bug in one does not open the network:

1. **OpenShell:** the sandbox has no network interface other than loopback. The supervisor makes each connection for it, and only to a host, port, and program that the policy allows. Everything else is denied and logged.
2. **NetworkPolicy:** the Pod can reach the Coder server, public addresses on the profile's ports, and DNS. No private ranges, so no other Pods, no VPC, and no cloud metadata.

The supervisor runs outside the sandbox, so code in the workspace cannot change its rules.

- **Coder:** the Coder agent and Claude Code can reach the access URL, and so can every program they start, such as the shells in your terminal.
- **Profile hosts:** every program can reach them.

To open a host for a running workspace only, run this in the Pod's `launcher` container, for example with `kubectl exec -it <pod> -c launcher -- bash`:

```sh
openshell policy update "$SANDBOX_NAME" --rule-name extra \
  --binary /usr/bin/curl --add-endpoint example.com:443 --wait
```

The change is gone after the next stop, and the NetworkPolicy must also allow the port. To see blocked requests, run `openshell logs "$SANDBOX_NAME" --since 5m --source sandbox`.

### Network ingress

Every profile blocks all ingress to the Pod. The Coder agent dials out to the Coder server and connects only through the Coder DERP relay, so the web terminal, code-server, `coder ssh`, port forwarding, and desktop IDEs all relay through Coder.

### Network egress

| Profile                       | Can reach, in addition to Coder                                     |
| ----------------------------- | ------------------------------------------------------------------- |
| Fully isolated (default)      | Nothing                                                             |
| GitHub only                   | GitHub host names on 443                                            |
| GitHub and package registries | GitHub, npm, the Go module proxy, and PyPI on 443                   |
| Custom                        | The host names and ports that you type. No preset, so a cold start. |

There is no Public internet profile, because OpenShell 0.1.5 has no rule for any public host. With Custom, the form shows a list of host names and a choice of ports 443, 80, and 22. `*.example.com` matches one label, such as `api.example.com`, and `**.example.com` matches any depth. Neither matches `example.com` itself, so add it too if you need it. The form rejects IP addresses, names without a dot, `*.com`, and cluster names such as `.svc` or `.local`, and the build checks them again.

## Limits

- The Docker daemon is privileged inside the VM. Code that escapes the sandbox and the supervisor can control the VM, but not the node.
- The NetworkPolicy allows any public address on 443 and the profile's ports, for image pulls and the supervisor. Only the OpenShell policy limits the hosts that the sandbox can reach.
- OpenShell decrypts HTTPS by default. It adds its own CA through `SSL_CERT_FILE` and similar variables, so it can read the traffic it allows.
- There are no direct connections, so all traffic to the workspace relays through Coder.
- If the launcher container exits, Kubernetes restarts it, and it replaces the sandbox. The home stays, but running programs stop.
- An allowed host that stores user content, such as GitHub, can receive data from the workspace.
- Each prebuild is a running Kata VM, so it costs the same as a running workspace.
- With the AI Gateway on, each start gives the workspace a new Coder token with only the `user:read_personal` scope, which the AI Gateway accepts. Code in the workspace can use it for AI requests. Coder cannot revoke it on stop, so it stays valid until the default token lifetime ends, and it shows in the owner's token list as `ai-gateway-<workspace>-<time>`.
- No root, no Docker in the sandbox, IPv4 only.
