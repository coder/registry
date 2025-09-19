---
display_name: Hetzner Cloud Server (Linux)
description: Provision Hetzner Cloud servers as Coder workspaces with networking and volumes
icon: ../../../../.icons/hetzner.svg
verified: false
tags: [vm, linux, hetzner, cloud, germany]
---

# Remote Development on Hetzner Cloud

Provision Hetzner Cloud servers as [Coder workspaces](https://coder.com/docs/workspaces) with this template.

This template provides a comprehensive Hetzner Cloud setup with:
- **Dynamic Configuration**: Server types, locations, and images loaded from JSON
- **Smart Validation**: Prevents invalid server type/location combinations  
- **Multiple Server Types**: Shared, dedicated, and CPU-optimized instances
- **Global Locations**: Germany, Finland, and USA datacenters
- **Persistent Storage**: Home volumes that survive workspace restarts
- **Secure Networking**: Private networks with firewall rules
- **Clean Architecture**: Minimal JSON configuration for easy maintenance

## Prerequisites

To deploy workspaces as Hetzner Cloud servers, you'll need:

- Hetzner Cloud [API token](https://docs.hetzner.cloud/#authentication)
- Hetzner Cloud project (create one in the [Hetzner Cloud Console](https://console.hetzner.cloud/))
- **SSH Keys**: Upload your SSH public keys to your Hetzner Cloud account (the template will use all available keys)

### Authentication

This template assumes that the Coder Provisioner is run in an environment that is authenticated with Hetzner Cloud.

Set the `HCLOUD_TOKEN` environment variable to your Hetzner Cloud API token, or provide it via the `hcloud_token` variable in your `terraform.tfvars` file.

For other authentication methods, consult the [Hetzner Cloud Terraform provider documentation](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs).

### Image Name Verification

The template uses Hetzner's official image names. To verify current available images:

```bash
# Set your API token
export HCLOUD_TOKEN="your-hetzner-cloud-api-token"

# List all available images
curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/images" | \
  jq '.images[] | select(.type=="system") | .name'
```

If you encounter image-related errors, check that the image names in `hetzner-config.json` match the official names exactly (some may include architecture suffixes like `-amd64`).

## Architecture

This template provisions the following resources:

- **Hetzner Cloud server** (ephemeral, deleted on workspace stop)
- **Persistent volume** (mounted to `/home/<username>`, survives workspace restarts)
- **Private network** with subnet for secure communication
- **Firewall** with rules for SSH, HTTP, HTTPS, and development ports
- **SSH keys** automatically loaded from your Hetzner Cloud account

### Lifecycle Management

- **Workspace start**: Server and volume are created, volume is attached
- **Workspace stop**: Server is destroyed, but volume persists
- **Workspace restart**: New server is created and existing volume is reattached

This means that when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace, modify the server image or use a [startup script](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script).

## Server Types

The template supports all major Hetzner Cloud server types:

### Shared vCPU (Cost-effective)
- **CX11**: 1 vCPU, 4 GB RAM
- **CX21**: 2 vCPU, 8 GB RAM  
- **CX22**: 2 vCPU, 4 GB RAM (AMD)
- **CX31**: 2 vCPU, 8 GB RAM
- **CX32**: 4 vCPU, 8 GB RAM (AMD)
- **CX41**: 4 vCPU, 16 GB RAM
- **CX42**: 8 vCPU, 16 GB RAM (AMD)
- **CX51**: 8 vCPU, 32 GB RAM
- **CX52**: 16 vCPU, 32 GB RAM (AMD)

### Dedicated vCPU (High Performance)
- **CCX13**: 2 vCPU, 8 GB RAM
- **CCX23**: 4 vCPU, 16 GB RAM
- **CCX33**: 8 vCPU, 32 GB RAM
- **CCX43**: 16 vCPU, 64 GB RAM
- **CCX53**: 32 vCPU, 128 GB RAM
- **CCX63**: 48 vCPU, 192 GB RAM

### CPU-Optimized
- **CPX11**: 2 vCPU, 4 GB RAM
- **CPX21**: 3 vCPU, 8 GB RAM
- **CPX31**: 4 vCPU, 16 GB RAM
- **CPX41**: 8 vCPU, 32 GB RAM
- **CPX51**: 16 vCPU, 64 GB RAM

## Locations

Available locations:
- **Falkenstein, Germany** (fsn1) - Primary location
- **Nuremberg, Germany** (nbg1) - Secondary location
- **Helsinki, Finland** (hel1) - EU Nordic
- **Ashburn, Virginia, USA** (ash) - US East Coast
- **Hillsboro, Oregon, USA** (hil) - US West Coast

## Supported Operating Systems

- Ubuntu 24.04 LTS
- Ubuntu 22.04 LTS (default)
- Ubuntu 20.04 LTS
- Debian 12
- Debian 11
- CentOS Stream 9
- Fedora 39
- Rocky Linux 9
- AlmaLinux 9

## Configuration

### Required Variables

```hcl
# terraform.tfvars
hcloud_token = "your-hetzner-cloud-api-token"
```

### Maintaining Configuration

The template uses `hetzner-config.json` for dynamic configuration:

- **Server Types**: Add new server types with their specifications
- **Locations**: Add new Hetzner datacenters as they become available  
- **Images**: Update with current Hetzner image names (verify with API)
- **Availability**: Map server type restrictions per location

**Example**: Adding a new server type:
```json
"cx62": { "name": "CX62 (16 vCPU, 64 GB RAM, AMD)", "vcpus": 16, "memory": 64 }
```

**Important**: Always verify image names match Hetzner's official names exactly to avoid provisioning errors.

### Optional Variables

All other parameters can be configured through the Coder workspace creation interface:

- **Location**: Choose the datacenter location
- **Server Type**: Select from available server configurations
- **Operating System**: Choose your preferred Linux distribution from the curated list
- **Custom Image Override**: Optionally specify a custom Hetzner Cloud image name (overrides the OS selection)
- **Home Volume Size**: Set the size of persistent storage (10-1000 GB)

### Custom Images

You can use custom images in two ways:

1. **Override Field**: Leave the "Custom Image Override" field empty to use the selected OS, or enter a custom image name to override it
2. **Examples**: 
   - `my-custom-snapshot` - Your own Hetzner Cloud snapshot
   - `debian-12-amd64` - Specific architecture variant
   - `ubuntu-24.04` - Newer image not yet in the dropdown list

The custom override takes precedence over the dropdown selection, allowing you to use any valid Hetzner Cloud image name.

## Security

The template includes:

- Private networking for secure inter-service communication
- Firewall rules allowing only necessary ports (22, 80, 443, 8080)
- SSH key authentication
- User isolation through cloud-init configuration

## Cost Optimization

- Servers are destroyed when workspaces stop, minimizing compute costs
- Volumes persist but are only charged for storage when servers are stopped
- Choose appropriate server types based on workload requirements
- Consider using shared vCPU instances for development workloads

## Troubleshooting

### Invalid Server Type/Location Combination

The template includes validation to prevent selecting server types that aren't available in certain locations. If you encounter this error, choose a different server type or location combination.

### Image Not Found Errors

If you get errors like "image not found" or "invalid image name":

1. **Verify Image Names**: Check current available images using the API:
   ```bash
   curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
     "https://api.hetzner.cloud/v1/images" | \
     jq '.images[] | select(.type=="system") | .name' | sort
   ```

2. **Update JSON Configuration**: Edit `hetzner-config.json` to match exact image names from Hetzner
3. **Common Issues**: 
   - Some images may have architecture suffixes (e.g., `debian-12` vs `debian-12-amd64`)
   - Image names may change over time as new versions are released
   - Deprecated images are removed from the available list

4. **Test Locally**: Before using in Coder, test image names with basic Terraform:
   ```hcl
   resource "hcloud_server" "test" {
     name        = "test"
     server_type = "cx11"
     image       = "ubuntu-22.04"  # Test this image name
     location    = "fsn1"
   }
   ```

### Volume Mount Issues

If the home directory doesn't mount properly:
1. Check that the volume is attached to the server
2. Verify the cloud-init configuration is applied correctly
3. Ensure the filesystem is formatted as ext4

### Network Connectivity Issues

If you can't connect to development servers:
1. Verify firewall rules allow the required ports
2. Check that the private network is configured correctly
3. Ensure the server has a public IP address

## Notes

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform configuration to extend the template to support your specific use case.

> [!IMPORTANT]
> The SSH key in this template is a placeholder. In a production environment, you should replace it with your actual SSH public key or remove the SSH key resource entirely if not needed.

> [!WARNING]
> Some server types may not be available in all locations. The template includes validation to prevent invalid combinations, but availability can change over time.
