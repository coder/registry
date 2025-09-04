---
display_name: JFrog Xray Integration
description: Display container image vulnerability scan results from JFrog Xray in workspace metadata
icon: /icon/security.svg
maintainer_github: coder
verified: true
tags: [security, scanning, jfrog, xray, vulnerabilities]
---

# JFrog Xray Integration

This module integrates JFrog Xray vulnerability scanning results into Coder workspace metadata. It displays vulnerability counts (Critical, High, Medium, Low) for container images directly on the workspace page.

```tf
module "jfrog_xray" {
  source      = "registry.coder.com/modules/jfrog-xray/coder"
  version     = "1.0.0"
  
  resource_id = docker_container.workspace.id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

## Features

- **Automatic Vulnerability Display**: Shows vulnerability counts from JFrog Xray scans
- **Real-time Results**: Fetches latest scan results during workspace provisioning
- **Flexible Image Specification**: Supports various image path formats
- **Secure Token Handling**: Sensitive token management with Terraform
- **Universal Compatibility**: Works with any workspace type that uses container images

## Prerequisites

1. **JFrog Artifactory**: Container images must be stored in JFrog Artifactory
2. **JFrog Xray**: Xray must be configured to scan your repositories
3. **Access Token**: Valid JFrog access token with Xray read permissions
4. **Scanned Images**: Images must have been scanned by Xray (scans can be triggered automatically or manually)

## Usage

### Basic Usage

```hcl
module "jfrog_xray" {
  source      = "registry.coder.com/modules/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id = docker_container.workspace.id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

### Advanced Usage with Custom Configuration

```hcl
module "jfrog_xray" {
  source      = "registry.coder.com/modules/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id  = docker_container.workspace.id
  xray_url     = "https://example.jfrog.io/xray"
  xray_token   = var.jfrog_access_token

  # Specify repo and path separately for more control
  repo         = "docker-local"
  repo_path    = "/codercom/enterprise-base:v2.1.0"

  display_name = "Container Security Scan"
  icon         = "/icon/shield.svg"
}
```

### Complete Workspace Template Example

```hcl
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "jfrog_access_token" {
  description = "JFrog access token for Xray API"
  type        = string
  sensitive   = true
}

data "coder_workspace" "me" {}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "example.jfrog.io/docker-local/codercom/enterprise-base:latest"
  name  = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"

  # Container configuration...
}

# Add Xray vulnerability scanning
module "jfrog_xray" {
  source      = "registry.coder.com/modules/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id = docker_container.workspace[0].id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

## Variables

| Name           | Description                                                                  | Type     | Default                      | Required |
| -------------- | ---------------------------------------------------------------------------- | -------- | ---------------------------- | -------- |
| `resource_id`  | The resource ID to attach the vulnerability metadata to                      | `string` | n/a                          | yes      |
| `xray_url`     | The URL of the JFrog Xray instance                                           | `string` | n/a                          | yes      |
| `xray_token`   | The access token for JFrog Xray authentication                               | `string` | n/a                          | yes      |
| `image`        | The container image to scan in format 'repo/path:tag'                        | `string` | n/a                          | yes      |
| `repo`         | The JFrog Artifactory repository name (auto-extracted if not provided)       | `string` | `""`                         | no       |
| `repo_path`    | The repository path with image name and tag (auto-extracted if not provided) | `string` | `""`                         | no       |
| `display_name` | The display name for the vulnerability metadata section                      | `string` | `"Security Vulnerabilities"` | no       |
| `icon`         | The icon to display for the vulnerability metadata                           | `string` | `"/icon/security.svg"`       | no       |

## Outputs

This module creates workspace metadata that displays:

- **Image**: The scanned container image
- **Total Vulnerabilities**: Total count of all vulnerabilities
- **Critical**: Count of critical severity vulnerabilities
- **High**: Count of high severity vulnerabilities
- **Medium**: Count of medium severity vulnerabilities
- **Low**: Count of low severity vulnerabilities

## Image Format Examples

The module supports various image path formats:

```hcl
# Standard format
image = "docker-local/codercom/enterprise-base:latest"

# With registry URL (will extract repo and path)
image = "docker-local/myorg/myapp:v1.2.3"

# Complex nested paths
image = "docker-local/team/project/service:main-abc123"
```

## Security Considerations

1. **Token Security**: Always use Terraform variables or external secret management for the `xray_token`
2. **Network Access**: Ensure Coder can reach your JFrog Xray instance
3. **Permissions**: The access token needs read permissions for Xray scan results
4. **Scan Coverage**: Ensure your images are being scanned by Xray policies

## Troubleshooting

### Common Issues

**"No scan results found"**

- Verify the image exists in Artifactory
- Check that Xray has scanned the image
- Confirm the image path format is correct

**"Authentication failed"**

- Verify the access token is valid
- Check token permissions include Xray read access
- Ensure the Xray URL is correct

**"Module fails to apply"**

- Verify network connectivity to JFrog instance
- Check Terraform provider versions
- Review Coder logs for detailed error messages

### Debugging

Enable Terraform debugging to see detailed API calls:

```bash
export TF_LOG=DEBUG
coder templates plan <template-name>
```

## Integration with Existing Guides

This module complements the existing [JFrog Xray integration guide](https://coder.com/docs/v2/latest/guides/xray-integration) by providing a Terraform-native approach that:

- Works with all workspace types (not just Kubernetes)
- Doesn't require deploying additional services
- Integrates directly into workspace templates
- Provides real-time vulnerability information

## Related Resources

- [JFrog Artifactory Integration Guide](https://coder.com/docs/v2/latest/guides/artifactory-integration)
- [Coder Metadata Resource Documentation](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata)
- [JFrog Xray Terraform Provider](https://registry.terraform.io/providers/jfrog/xray/latest)
