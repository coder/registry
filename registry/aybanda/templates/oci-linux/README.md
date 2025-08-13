---
display_name: Oracle Cloud Infrastructure (Linux)
description: Provision Oracle Cloud Infrastructure VMs as Coder workspaces
verified: false
tags: [vm, linux, oci, oracle]
---

# Remote Development on Oracle Cloud Infrastructure (Linux)

Provision Oracle Cloud Infrastructure (OCI) VMs as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### Authentication

This template assumes that coderd is run in an environment that is authenticated with Oracle Cloud Infrastructure. The recommended authentication methods are:

1. **Instance Principal** (Recommended for production): Run Coder on an OCI instance with proper IAM policies
2. **API Key**: Set environment variables `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, and `OCI_PRIVATE_KEY_PATH`
3. **Configuration File**: Use `~/.oci/config` file

For detailed authentication setup, see the [OCI Terraform provider documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs#authentication).

### Required IAM Policies

The following IAM policies are required for the template to work:

```json
{
  "statements": [
    {
      "effect": "Allow",
      "action": [
        "core:instance:create",
        "core:instance:delete",
        "core:instance:get",
        "core:instance:update",
        "core:volume:create",
        "core:volume:delete",
        "core:volume:get",
        "core:volume:update",
        "core:volumeAttachment:create",
        "core:volumeAttachment:delete",
        "core:volumeAttachment:get",
        "core:vcn:create",
        "core:vcn:delete",
        "core:vcn:get",
        "core:vcn:update",
        "core:subnet:create",
        "core:subnet:delete",
        "core:subnet:get",
        "core:subnet:update",
        "core:internetGateway:create",
        "core:internetGateway:delete",
        "core:internetGateway:get",
        "core:internetGateway:update",
        "core:routeTable:create",
        "core:routeTable:delete",
        "core:routeTable:get",
        "core:routeTable:update",
        "core:securityList:create",
        "core:securityList:delete",
        "core:securityList:get",
        "core:securityList:update",
        "core:image:get",
        "identity:compartment:get"
      ],
      "resource": "*"
    }
  ]
}
```

## Architecture

This template provisions the following resources:

- **OCI VM** (ephemeral, deleted on stop)
- **OCI Block Volume** (persistent, mounted to `/home/coder`)
- **VCN with Internet Gateway** (for network connectivity)
- **Security List** (with SSH, HTTP, and HTTPS access)

The template uses Ubuntu 22.04 LTS as the base image and includes:

- Code Server for web-based development
- JetBrains Gateway for IDE access
- Persistent home directory storage
- Automatic Coder agent installation

## Usage

1. **Set up authentication** using one of the methods above
2. **Create a compartment** in your OCI tenancy
3. **Deploy the template** with your compartment OCID
4. **Optionally provide an SSH public key** for direct SSH access

### Template Variables

- `compartment_ocid`: The OCID of your OCI compartment
- `ssh_public_key`: (Optional) SSH public key for direct access

### Instance Shapes

The template supports various OCI instance shapes:

- **VM.Standard.A1.Flex**: ARM-based flexible shapes (1-4 OCPUs, 6-24 GB RAM)
- **VM.Standard.E2.1.Micro**: Cost-effective micro instances
- **VM.Standard.E2.1.Small**: Small instances for development
- **VM.Standard.E2.1.Medium**: Medium instances for larger workloads
- **VM.Standard.E3.Flex**: AMD-based flexible shapes

### Regions

The template supports all major OCI regions:

- **Americas**: US East (Ashburn), US West (Phoenix), Canada Southeast (Montreal)
- **Europe**: UK South (London), Germany Central (Frankfurt), Netherlands Northwest (Amsterdam), Switzerland North (Zurich)
- **Asia Pacific**: Japan East (Tokyo), Japan Central (Osaka), South Korea Central (Seoul), Australia Southeast (Sydney), India West (Mumbai), India South (Hyderabad)
- **Middle East**: Saudi Arabia West (Jeddah), UAE East (Dubai)
- **South America**: Brazil East (São Paulo), Chile (Santiago)

## Cost Optimization

- Use **VM.Standard.A1.Flex** shapes for cost-effective ARM-based instances
- Choose **VM.Standard.E2.1.Micro** for minimal development workloads
- Consider **VM.Standard.E3.Flex** for AMD-based workloads requiring more memory
- Use smaller home disk sizes (50 GB) for basic development
- Stop workspaces when not in use to avoid charges

## Security

- Instances are created with public IP addresses for Coder access
- SSH access is restricted to the provided public key
- Security lists allow only necessary ports (22, 80, 443)
- All resources are tagged with `Coder_Provisioned = true`

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure proper OCI authentication is configured
2. **Permission Errors**: Verify IAM policies are correctly set
3. **Network Issues**: Check VCN and security list configuration
4. **Volume Attachment**: Ensure the home volume is properly attached

### Debugging

- Check OCI console for instance status and logs
- Verify network connectivity and security list rules
- Review Terraform logs for detailed error messages

## Contributing

This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.

For issues and contributions, please visit the [Coder Registry repository](https://github.com/coder/registry).

## Contributors

- [aybanda](https://github.com/aybanda)
