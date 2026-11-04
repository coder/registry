---
display_name: AWS Fargate (EKS)
description: Provision Kubernetes Deployments on Amazon EKS Fargate as Coder workspaces, with home directories on Amazon EFS
icon: ../../../../.icons/aws.svg
verified: false
tags: [kubernetes, container, aws, eks, fargate, efs]
---

# Remote Development on Amazon EKS Fargate

Provision Kubernetes Deployments on [AWS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html) as [Coder workspaces](https://coder.com/docs/workspaces) with this example template. Fargate runs each workspace Pod in its own VM-isolated environment, so workspaces don't share a kernel or a node, and you don't manage EC2 worker nodes for them. Home directories live on [Amazon EFS](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html), because Fargate Pods can't mount Amazon EBS volumes.

This template starts from the [Kubernetes (Deployment)](../../../coder/templates/kubernetes) template and changes only what Fargate needs:

- Workspace Pods carry labels that match your Fargate profile (`fargate_pod_labels`).
- CPU and memory requests equal the limits, because Fargate Pods run with Guaranteed QoS and are sized from their requests.
- CPU and memory options map to Fargate configurations.
- The home volume is a statically provisioned EFS PersistentVolume backed by a per-workspace EFS access point, instead of a dynamically provisioned block volume.
- Pod anti-affinity is removed, because every Fargate Pod already runs on its own node.

<!-- TODO: Add screenshot -->

## Prerequisites

### Infrastructure

**Cluster**: An existing Amazon EKS cluster in `aws_region`. Coder itself can run on the same cluster (on EC2 nodes, EKS Auto Mode, or Fargate) or elsewhere.

**Fargate profile**: A [Fargate profile](https://docs.aws.amazon.com/eks/latest/userguide/fargate-profile.html) whose selector matches the workspace namespace and every label in `fargate_pod_labels`. A Pod must match a profile when it's scheduled. Pods that don't match run on other cluster capacity, if any, or stay `Pending`. The profile needs:

- A [Pod execution role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html) with the `AmazonEKSFargatePodExecutionRolePolicy` managed policy.
- Private subnets only (default route through a NAT gateway, not an internet gateway). Workspaces need outbound access to your Coder access URL and your container registry.

```bash
aws eks create-fargate-profile \
  --cluster-name <cluster-name> \
  --fargate-profile-name coder-workspaces \
  --pod-execution-role-arn arn:aws:iam::<account-id>:role/<pod-execution-role> \
  --subnets <private-subnet-a> <private-subnet-b> \
  --selectors 'namespace=coder-ws,labels={compute=fargate}'
```

**Namespace**: Create the workspace namespace before you create workspaces, and set the `namespace` variable to it.

```bash
kubectl create namespace coder-ws
```

**EFS file system**: An EFS file system in the cluster's VPC. Set `efs_file_system_id` to its ID. It needs:

- A mount target in each Availability Zone used by the Fargate profile's subnets.
- A mount target security group that allows inbound NFS (TCP 2049) from workspace Pods, either from the EKS [cluster security group](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) or from the CIDR ranges of the Fargate subnets. Fargate Pods use the cluster security group unless you assign security groups for Pods.

You don't need to install the EFS CSI driver for Fargate. Fargate Pods mount EFS automatically, but only with static provisioning, which is why the template creates each PersistentVolume itself instead of using dynamic provisioning.

**StorageClass**: A StorageClass named `efs-static` (or set `efs_storage_class_name`). The template uses it only to match each workspace's PersistentVolume to its claim.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-static
provisioner: efs.csi.aws.com
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

### Provisioner permissions

The template manages both AWS and Kubernetes resources, so the Coder provisioner (the Coder server or an external provisioner) needs permissions in both.

**AWS**: The AWS provider uses the standard credential chain. On EKS, use [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) or [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) for the Coder service account. If Coder itself runs on Fargate, use IRSA, because EKS Pod Identity doesn't support Fargate Pods. The provisioner needs to manage EFS access points:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageCoderWorkspaceAccessPoints",
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:CreateAccessPoint",
        "elasticfilesystem:DeleteAccessPoint",
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:TagResource",
        "elasticfilesystem:UntagResource",
        "elasticfilesystem:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

Scope `Resource` to your file system and its access points if your security policy requires it.

**Kubernetes**: The provisioner creates Deployments and PersistentVolumeClaims in the workspace namespace, and PersistentVolumes, which are cluster-scoped. The default RBAC in the Coder Helm chart (`coder.serviceAccount.workspacePerms`) covers only the release namespace.

- If workspaces use a separate namespace, list it under `coder.serviceAccount.workspaceNamespaces` in your Helm values, or create your own Role and RoleBinding there.
- Grant access to PersistentVolumes with a ClusterRole. Adjust the service account name and namespace to match your Coder installation.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: coder-workspace-persistentvolumes
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: coder-workspace-persistentvolumes
subjects:
  - kind: ServiceAccount
    name: coder
    namespace: coder
roleRef:
  kind: ClusterRole
  name: coder-workspace-persistentvolumes
  apiGroup: rbac.authorization.k8s.io
```

### Workspace image

This template exposes an `image` variable, as in the [Kubernetes (Deployment)](../../../coder/templates/kubernetes#workspace-image) template. See that template for image options. On Fargate, every workspace start pulls the image onto a fresh node, so smaller images start faster. Make sure the registry is reachable from the profile's private subnets, through the NAT gateway or [VPC endpoints for Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html).

### Authentication

This template authenticates to Kubernetes using a `~/.kube/config`, if present on the server, or via built-in authentication if the Coder provisioner is running on Kubernetes with an authorized ServiceAccount. To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Variables

| Name                     | Default                        | Description                                                                |
| ------------------------ | ------------------------------ | -------------------------------------------------------------------------- |
| `namespace`              | (required)                     | Workspace namespace. Must match your Fargate profile's namespace selector. |
| `efs_file_system_id`     | (required)                     | EFS file system for home directories, for example `fs-0123456789abcdef0`.  |
| `aws_region`             | `us-east-1`                    | Region of the EKS cluster and EFS file system.                             |
| `efs_storage_class_name` | `efs-static`                   | StorageClass used to bind each workspace's PersistentVolume to its claim.  |
| `fargate_pod_labels`     | `{ compute = "fargate" }`      | Labels that match your Fargate profile's label selector.                   |
| `image`                  | `codercom/example-base:ubuntu` | Workspace container image.                                                 |
| `use_kubeconfig`         | `false`                        | Use `~/.kube/config` on the Coder host instead of in-cluster credentials.  |

For example:

```bash
coder templates push aws-fargate -d . \
  --variable namespace=coder-ws \
  --variable efs_file_system_id=fs-0123456789abcdef0 \
  --variable aws_region=us-east-1
```

To override `fargate_pod_labels`, pass a variables file with `--variables-file`.

## Architecture

This template provisions the following resources:

- EFS access point rooted at `/workspaces/<workspace ID>`, which enforces UID and GID `1000` (persistent)
- Kubernetes PersistentVolume and PersistentVolumeClaim bound to that access point, mounted on `/home/coder` (persistent)
- Kubernetes Deployment with one Pod on Fargate (ephemeral)

When the workspace stops, Coder deletes the Deployment and Fargate releases the Pod's compute. The access point, PersistentVolume, and claim remain, so the home directory is there on the next start. Any tools or files outside the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the container image. Alternatively, individual developers can [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.

When the workspace is deleted, Coder deletes the access point, PersistentVolume, and claim, but not the files. The data stays on the file system under `/workspaces/<workspace ID>` until you remove it, for example from a Pod or instance that mounts the file system root.

## Fargate considerations

- **Startup time**: Fargate provisions compute and pulls the image for each Pod, so workspaces take longer to start than on warm EC2 nodes.
- **Sizing and cost**: Fargate adds 256 MB to the Pod's memory request and rounds up to the nearest supported vCPU and memory combination, which is what you pay for. For example, 1 vCPU with 8 GB provisions 2 vCPUs with 9 GB. See [Fargate Pod configuration](https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html).
- **Unsupported workloads**: Fargate doesn't support privileged containers, DaemonSets, `hostPort`, `hostNetwork`, or GPUs. Docker-in-Docker and other tools that need privileged mode won't run. Use an EC2-based template for these.
- **Storage**: EFS is a network file system. Workloads with many small file operations, such as large dependency installs, can be slower than on block storage.
- **Patching**: AWS patches Fargate by evicting Pods. The Deployment recreates the Pod, which restarts the workspace but keeps the home directory. See [Fargate OS patching](https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-patching.html).
- **Access points**: Each workspace uses one EFS access point. Check the [EFS quota](https://docs.aws.amazon.com/efs/latest/ug/limits.html) for access points per file system.
- **AWS access from workspaces**: To give workspaces AWS credentials, create a service account with an IRSA role in the workspace namespace and set `service_account_name` in the Pod spec. EKS Pod Identity doesn't support Fargate Pods.

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
