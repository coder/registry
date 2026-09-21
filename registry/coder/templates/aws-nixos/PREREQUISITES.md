# Prerequisites

## Authentication

This template authenticates to AWS using the provider's default [authentication methods](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration).

The simplest way, without editing the template, is environment variables (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) or a [credentials file](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-format).
If you are running Coder on a VM, that file must be at `/home/coder/aws/credentials`.

Credentials belong in the environment of the **provisioner process** — `coder server`, or your
external provisioner — and not in Terraform variables. Template variables surface in workspace
parameters and build logs, so a credential passed that way is readable by anyone who can view a
build. Restart the provisioner after changing them.

Prefer, in order:

1. An **instance profile** (Coder on EC2) or **IRSA** (Coder on EKS). No long-lived secret exists.
2. A long-lived, low-privilege identity plus `assume_role` in the provider block.
3. Static access keys.

Avoid `AWS_SESSION_TOKEN` from STS for a provisioner: it expires, and it will expire in the middle
of a build.

## A default VPC in the selected region

Like the `aws-linux` template, this one launches into the default VPC of the region chosen by the
`aws_region` parameter and does not take a subnet or security group. Regions without a default VPC
fail at apply with `VPCIdNotSpecified`. Either pick a region that has one, or create one with
`aws ec2 create-default-vpc --region <region>`.

## Required permissions / policy

The following sample policy allows Coder to create EC2 instances and modify instances it
provisioned.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
        "ec2:GetDefaultCreditSpecification",
        "ec2:DescribeIamInstanceProfileAssociations",
        "ec2:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceStatus",
        "ec2:CreateTags",
        "ec2:RunInstances",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeImages",
        "ec2:ModifyDefaultCreditSpecification",
        "ec2:DescribeVolumes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CoderResources",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstanceAttribute",
        "ec2:UnmonitorInstances",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DeleteTags",
        "ec2:MonitorInstances",
        "ec2:CreateTags",
        "ec2:RunInstances",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyInstanceCreditSpecification"
      ],
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Coder_Provisioned": "true"
        }
      }
    }
  ]
}
```

## Network egress from the workspace

Unlike the stock AWS templates, workspaces here must reach more than the Coder deployment. A NixOS
instance resolves and builds its own configuration on boot, so it needs outbound HTTPS to:

| Host                                 | Why                                                      |
| ------------------------------------ | -------------------------------------------------------- |
| your Coder access URL                | agent connection and the log API                         |
| `cache.nixos.org`                    | binary cache; without it everything is built from source |
| `github.com` / `codeload.github.com` | fetching your flake and its nixpkgs input                |
| any extra substituters you configure | binary caches declared in your flake                     |

No inbound rules are required. If you plan to use the SSH rescue path described in the README, open
port 22 from your own address — the default VPC security group does not allow it.
