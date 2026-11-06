---
display_name: "Scaleway Instance"
description: "A workspace spun up on a Scaleway Instance"
icon: "../../../../.icons/scaleway.svg"
verified: false
tags: ["scaleway", "vm", "linux"]
---

# Scaleway Instance Template

This template provisions Coder workspaces on [Scaleway](https://www.scaleway.com/) cloud instances with full customization options for regions, instance types, operating systems, and storage configurations.

## Features

- **Multi-region support**: Choose from France (Paris), Netherlands (Amsterdam), or Poland (Warsaw)
- **Flexible instance sizing**: Wide range of instance types from development to high-performance computing
- **Multiple OS options**: Debian 12/13, Ubuntu 24.04/26.04, and Fedora 44
- **Customizable storage**: Adjustable disk size with configurable IOPS
- **IPv4 and IPv6 networking**: Dual-stack IP configuration for enhanced connectivity

## Prerequisites

### Scaleway Account Setup

1. Create a [Scaleway account](https://console.scaleway.com/)
2. Create a new project or use an existing one
3. Generate API credentials:
   - Go to **IAM** > **API Keys** in the Scaleway Console
   - Create a new API key
   - Note down the **Access Key** and **Secret Key**
   - Copy your **Project ID** from the project settings
   - Give permissions for **BlockStorageFullAccess**, **ProjectReadOnly**, **InstancesFullAccess** as a starting point

## Architecture

This template creates the following resources for each workspace:

### Persistent Resources

- **Block Volume**: Mounted as user's home directory (preserves all data, configs, and projects)

### Ephemeral Resources (destroyed when workspace stops)

- **Scaleway Instance**: Virtual machine created fresh on each workspace start
- **IPv4 Address**: Routed IPv4 address assigned dynamically
- **IPv6 Address**: Routed IPv6 address assigned dynamically
- **Cloud-init Configuration**: Automated setup of the Coder agent and persistent storage mounting

## Configuration Options

### Region Selection

Choose from three available regions:

- **France - Paris (fr-par)**: Default, lowest latency for European users
- **Netherlands - Amsterdam (nl-ams)**: Alternative European location
- **Poland - Warsaw (pl-waw)**: Eastern European option

### Instance Types

The instance type dropdown is filtered to the types available in the selected region, so the list differs between Paris, Amsterdam, and Warsaw. Windows-licensed (`-WIN`) types are excluded.

#### Development Instances

- **STARDUST1, DEV1, PLAY2**: Small, low-cost instances for light development

#### General Purpose and Production Instances

- **BASIC3, STANDARD3, COMPUTE3, MEMORY3**: Current-generation x86 families
- **POP2 Series** (including HC, HM, and HN variants): General purpose, compute, memory, and network optimized
- **GP1 and PRO2 Series**: Previous-generation general purpose instances

#### Specialized Instances

- **BASIC2 and STANDARD2**: ARM64 instances
- **L4 and RENDER**: GPU-enabled instances for AI/ML workloads (Paris only)

### Operating System Options

- **Debian 13 (Trixie)**: Latest Debian release
- **Debian 12 (Bookworm)**: Stable Debian LTS
- **Ubuntu 26.04 (Resolute)**: Latest Ubuntu LTS
- **Ubuntu 24.04 (Noble)**: Previous Ubuntu LTS
- **Fedora 44**: Cutting-edge features and packages

### Storage Configuration

- **Home Directory Size**: 10-500GB adjustable via slider (your entire home directory)
- **IOPS**: 5,000 or 15,000 IOPS options for performance tuning

## Template Components

### Included Tools

- **VS Code Server**: Browser-based IDE with full extension support
- **System Monitoring**: CPU, RAM, and disk usage metrics
- **Dotfiles Support**: Automatic dotfiles synchronization on workspace start
- **Custom Environment Variables**: Pre-configured welcome message

### Cloud-init Setup

The template uses cloud-init for:

- Automatic Coder agent installation and configuration
- User account setup with proper permissions
- Persistent home directory mounting (automatic disk partitioning and filesystem creation)
- Development tools initialization

## Usage

### Creating a Workspace

1. **Select Template**: Choose "Scaleway Instance" from your Coder templates
2. **Configure Region**: Pick your preferred Scaleway region
3. **Choose Instance**: Select instance type based on your performance needs
4. **Select OS**: Pick your preferred operating system
5. **Set Home Directory Size**: Adjust storage size (10-500GB) for your persistent home directory
6. **Create**: Launch your workspace

### Managing Costs

- **VM instances are destroyed** when workspace stops (zero compute costs when not in use)
- **IP addresses are released** when workspace stops (no static IP charges)
- **Home directory persists** on dedicated block volume (small storage cost only)
- **Fresh OS** on each workspace start with persistent user data
- Choose appropriate instance sizes for your workload requirements

## Customization

### Extending the Template

You can customize this template by:

1. **Adding Software**: Modify cloud-init scripts to install additional tools
2. **Custom Modules**: Include additional Coder modules from the registry
3. **Network Configuration**: Adjust security groups or network settings
4. **Startup Scripts**: Add custom initialization logic

## Maintenance

### Updating Instance Types

To update the available instance types, regenerate the `scaleway-config.json` file (requires an authenticated `scw` CLI):

```bash
for r in fr-par nl-ams pl-waw; do
  scw instance server-type list zone=$r-1 -o json | jq --arg r "$r" 'map(select(.name | endswith("-WIN") | not) | {name, cpu, gpu, ram, arch, regions: [$r]})'
done | jq -s 'add | group_by(.name) | map(.[0] + {regions: map(.regions[0])})' > scaleway-config.json
```

This pulls the latest instance types from each region's default zone (`<region>-1`, where workspaces are created) and records which regions offer each type, so the template can filter the dropdown by region. If you add a region to the template, add it to the loop as well.

To check which OS images are currently available, run `scw marketplace image list`.

## References

- [Scaleway Documentation](https://www.scaleway.com/en/docs/)
- [Scaleway Instance Types](https://www.scaleway.com/en/pricing/#instances)
- [Coder Templates Documentation](https://coder.com/docs/templates)
- [Terraform Scaleway Provider](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs)
