---
display_name: OpenShift
description: Provision OpenShift workspaces with arbitrary UIDs and persistent home directories under restricted-v2
icon: ../../../../.icons/openshift.svg
verified: false
tags: [openshift, kubernetes, container]
---

# OpenShift

Provision an OpenShift Deployment as a Coder workspace with a persistent home directory and code-server. Based on the [Kubernetes template](../kubernetes), this template lets OpenShift assign the workspace's user ID and volume group under the default `restricted-v2` Security Context Constraint (SCC).

## Prerequisites

Use an existing OpenShift project with `restricted-v2` available to its `default` service account, enough resource quota for the workspace, and a default StorageClass that provisions `ReadWriteOnce` volumes. The storage driver must honor the SCC-assigned `fsGroup` so a newly mounted home volume is writable. Set a different StorageClass when the cluster has no suitable default. NFS exports with fixed ownership may require administrator configuration; do not work around storage permissions by granting a privileged SCC.

Install the OpenShift CLI (`oc`) and the Coder CLI on your administration machine. Authenticate to the cluster and select the workspace project:

```sh
oc login <cluster-api-url>
oc project <workspace-project>
oc auth can-i use scc/restricted-v2 --as=system:serviceaccount:<workspace-project>:default
```

Checking another service account may require impersonation permission; ask your cluster administrator to verify SCC access if needed. No SCC changes are required by this template.

The **Coder provisioner**, rather than your local CLI, needs cluster credentials. When it runs inside the cluster, use its service account. When it runs outside, enable kubeconfig authentication and provide `~/.kube/config` on the provisioner's host. That identity needs `get`, `list`, `watch`, `create`, `update`, `patch`, and `delete` on `deployments.apps` and `persistentvolumeclaims` in the target project. Read access to pods, events, and pod logs is useful for troubleshooting. The workspace service account does not need those provisioning privileges, and its API token is not mounted in workspace pods.

The provisioner must reach the OpenShift API. Workspace pods must reach your Coder access URL for agent download and connection. Nodes need access to `quay.io` for the default image; code-server installation needs `code-server.dev`, GitHub, and GitHub release downloads. Adapt images and module installation to your organization's network policy before using a restricted network.

## Workspace image

The default [Devfile base developer image](https://github.com/devfile/developer-images/tree/main/base/ubi9) uses Red Hat UBI 9 and is pinned to an image digest. It provides Bash, curl, tar, Git, and an entrypoint that registers the arbitrary UID supplied by OpenShift. Its home directory is `/home/user`, writable by group 0. The template supplies agent bootstrap through container `args`, preserving that entrypoint; replacing `command` would bypass UID initialization.

You can substitute an image that supports the same home path, arbitrary UID, and entrypoint contract. Select a matching workspace architecture; the template schedules the pod onto Linux nodes with that architecture. The default is AMD64, with ARM64 also supported. Tools must be installed into the image or under the home directory: package installation with sudo and privileged container engines are not supported under `restricted-v2`.

See [Red Hat's image authoring guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/images/creating-images#use-uid_create-images) for the root-group permissions pattern. Image directory permissions alone do not set permissions on a mounted PVC; the storage requirement above still applies.

## Architecture

The Deployment and code-server app exist only while the workspace is started. The Deployment uses `Recreate` to avoid simultaneous pods attaching the same home volume. CPU and memory limits can be changed when rebuilding a workspace.

A separate PVC is mounted at `/home/user` and remains when the workspace is stopped. Its configuration is ignored after creation to avoid replacement when workspace metadata or template defaults change. Files outside the home directory are ephemeral. Deleting the workspace deletes its PVC; the StorageClass reclaim policy determines whether the underlying storage is retained. Back up important files before deletion.

The template does not specify `run_as_user`, `run_as_group`, or `fs_group`. OpenShift assigns these at admission. The pod requests non-root execution and `RuntimeDefault` seccomp, drops all container capabilities, and disables privilege escalation. It does not create SCCs or grant `anyuid`. See [OpenShift SCC documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/authentication_and_authorization/managing-pod-security-policies) and [Coder on OpenShift](https://coder.com/docs/install/server/openshift).

## Validation

Tested on OpenShift **4.21.30** (Red Hat Developer Sandbox on ROSA, AMD64) with Coder **2.36.7**, Terraform **1.16.4**, and the default image digest above. The cluster's default `gp3` StorageClass provisioned a 10 GiB home volume. The pod was admitted under `restricted-v2` with an OpenShift-assigned UID and volume group; the agent connected, and both the Coder terminal and code-server worked.

Stopping removed the Deployment and pod while preserving the same PVC. After restarting, the agent reconnected and a file created in the terminal and edited in code-server retained its contents. Deleting the disposable workspace removed its Deployment, pod, and PVC. Other OpenShift versions, storage drivers, and ARM64 clusters have not been tested end to end.

Run local configuration checks from this directory:

```sh
terraform init
terraform validate
terraform test
```

The Terraform tests use mocked providers to check security settings, entrypoint preservation, start/stop resource selection, and input validation. They do not connect to a cluster.

To repeat validation on your OpenShift cluster:

1. Record `oc version` (including the server version), Coder version, image digest, and StorageClass. Push the template to a test Coder deployment from the repository root:

   ```sh
   coder templates push openshift -d registry/coder/templates/openshift -m "OpenShift workspace validation"
   ```

   Supply the existing project and the provisioner's authentication mode when prompted. Create a workspace using the template and wait for the agent to connect.

2. Find its pod by workspace ID and verify the admitted SCC and assigned UID. Use the workspace's `id` from `coder list --output json`:

   ```sh
   WORKSPACE_ID=<workspace-uuid>
   POD=$(oc get pods -l "com.coder.workspace.id=$WORKSPACE_ID" -o jsonpath='{.items[0].metadata.name}')
   oc get pod "$POD" -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
   oc get pod "$POD" -o jsonpath='{.spec.containers[0].securityContext.runAsUser}{"\n"}'
   oc get namespace "$(oc project -q)" -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
   ```

   Confirm `restricted-v2` and a UID in the project's allocated range. A more privileged SCC is not a valid result.

3. Open the Coder web terminal and code-server. In the terminal, run `id`, `getent passwd "$(id -u)"`, and `printf 'persistent\n' > "$HOME/openshift-persistence-check"`. Confirm the editor can open and modify a file in the home directory.

4. Stop the workspace. Confirm its Deployment and pods are gone but its PVC remains. Restart it, confirm the agent reconnects, and verify the marker and edited file contents. Delete only this disposable test workspace and confirm its Deployment, pods, and PVC are gone.

5. Record the tested OpenShift version and observed results, including any differences from the environment documented above.
