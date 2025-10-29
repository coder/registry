# Cloud DevOps Workspace

A secure, company-standard DevOps environment for platform and cloud engineers.

This template deploys workspaces **into an existing Amazon EKS cluster** and provides developers with tools and credentials to work with **AWS, Azure, and GCP** from inside their workspace.

Supports multiple Infrastructure-as-Code frameworks — **Terraform**, **AWS CDK**, and **Pulumi** — for flexible, multi-cloud development.

---

## Features

- **Multi-Cloud Ready** — authenticate to AWS, Azure, or GCP from a single workspace
- **Runs on EKS** — leverages existing Kubernetes infrastructure for scaling and security
- **IaC Tools Included** — Terraform, Terragrunt, CDK, Pulumi, tfsec, and more
- **Secure Isolation** — each workspace runs in its own Kubernetes namespace
- **Configurable Auth** — supports IRSA (AWS), Federated Identity (Azure), and WIF (GCP)

---

## Variables

| Variable                                                      | Description                                                     | Type   | Default     |
| ------------------------------------------------------------- | --------------------------------------------------------------- | ------ | ----------- |
| `host_cluster_name`                                           | EKS cluster name where workspaces are deployed                  | string | —           |
| `iac_tool`                                                    | Infrastructure-as-Code framework (`terraform`, `cdk`, `pulumi`) | string | `terraform` |
| `enable_aws`                                                  | Enable AWS authentication and tools                             | bool   | `true`      |
| `enable_azure`                                                | Enable Azure authentication and tools                           | bool   | `false`     |
| `enable_gcp`                                                  | Enable GCP authentication and tools                             | bool   | `false`     |
| `aws_access_key_id` / `aws_secret_access_key`                 | AWS credentials (optional)                                      | string | `""`        |
| `azure_client_id` / `azure_client_secret` / `azure_tenant_id` | Azure credentials (optional)                                    | string | `""`        |
| `gcp_service_account`                                         | GCP Service Account JSON (optional)                             | string | `""`        |

---

## Runtime Architecture

| Layer                   | Platform           | Purpose                                                      |
| ----------------------- | ------------------ | ------------------------------------------------------------ |
| **Infrastructure**      | Amazon EKS         | Where Coder deploys and runs the workspaces                  |
| **Workspace Container** | Ubuntu-based image | Developer environment (Terraform, CDK, Pulumi, CLIs)         |
| **Cloud Access**        | AWS / Azure / GCP  | Target environments for deploying infrastructure or services |

---

## Required Permissions and Setup Steps

This template **runs on EKS** but allows developers inside the workspace to authenticate with **AWS, Azure, or GCP** using their own credentials or service identities.

### Coder & Infrastructure (Admin Setup)

Your Coder deployment must have:

- Network access to an **existing EKS cluster**
- The Coder Helm chart installed and healthy
- Terraform configured with access to the EKS API

#### **Minimum AWS IAM Permissions**

For the identity running the template (Coder service account, Terraform runner, or user):

```json
{
  "Effect": "Allow",
  "Action": [
    "eks:DescribeCluster",
    "eks:ListClusters",
    "sts:GetCallerIdentity",
    "sts:AssumeRole"
  ],
  "Resource": "*"
}
```
