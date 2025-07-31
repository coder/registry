# Moonlight/GameStream Module Implementation Plan

## Overview
Create a Coder module that automatically configures Moonlight streaming support for GPU-accelerated remote desktop access. The module will detect compatible workspaces and configure either NVIDIA GameStream or Sunshine server automatically.

## Module Structure
```
registry/registry/Majain004/modules/moonlight/
├── main.tf                    # Main Terraform module
├── README.md                  # Documentation
├── main.test.ts              # Automated tests
├── PR_DESCRIPTION.md         # PR template
└── scripts/
    ├── install-moonlight.ps1 # Windows installation
    ├── install-moonlight.sh  # Linux installation
    ├── detect-gpu.ps1        # GPU detection (Windows)
    └── detect-gpu.sh         # GPU detection (Linux)
```

## Features

### Core Functionality
- ✅ **Automatic GPU detection** - Identifies NVIDIA GPUs
- ✅ **GameStream/Sunshine configuration** - Auto-configures streaming server
- ✅ **Moonlight client setup** - Installs and configures client
- ✅ **Cross-platform support** - Windows and Linux compatibility
- ✅ **Coder app integration** - Exposes Moonlight as Coder app

### Technical Requirements
- **NVIDIA GPU detection** - Identifies compatible hardware
- **GameStream server setup** - Configures NVIDIA GameStream
- **Sunshine server setup** - Alternative for non-NVIDIA setups
- **Moonlight client installation** - Remote client setup
- **Network configuration** - Port forwarding and firewall rules

## Implementation Steps

### Phase 1: Module Structure
1. Create module directory under `Majain004` namespace
2. Set up Terraform configuration with variables
3. Create installation scripts for both platforms
4. Add GPU detection logic

### Phase 2: Core Functionality
1. Implement NVIDIA GameStream server setup
2. Implement Sunshine server setup
3. Create Moonlight client installation
4. Add network configuration

### Phase 3: Testing & Documentation
1. Write comprehensive tests
2. Create detailed documentation
3. Record demo video
4. Prepare PR with proper description

## Technical Details

### GPU Detection
```bash
# Windows (PowerShell)
Get-WmiObject -Class Win32_VideoController | Where-Object {$_.Name -like "*NVIDIA*"}

# Linux (Bash)
lspci | grep -i nvidia
```

### GameStream Configuration
- Enable NVIDIA GameStream in GeForce Experience
- Configure streaming settings
- Set up authentication

### Sunshine Configuration
- Install Sunshine server
- Configure streaming parameters
- Set up authentication

### Moonlight Client
- Install Moonlight client
- Configure connection settings
- Test connectivity

## Variables

```tf
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "os" {
  type        = string
  description = "Target operating system: 'windows' or 'linux'."
  validation {
    condition     = contains(["windows", "linux"], var.os)
    error_message = "os must be 'windows' or 'linux'"
  }
}

variable "streaming_method" {
  type        = string
  description = "Streaming method: 'gamestream' or 'sunshine'."
  default     = "auto"
  validation {
    condition     = contains(["auto", "gamestream", "sunshine"], var.streaming_method)
    error_message = "streaming_method must be 'auto', 'gamestream', or 'sunshine'"
  }
}

variable "port" {
  type        = number
  description = "Port for Moonlight streaming."
  default     = 47984
}

variable "quality" {
  type        = string
  description = "Streaming quality: 'low', 'medium', 'high', 'ultra'."
  default     = "high"
  validation {
    condition     = contains(["low", "medium", "high", "ultra"], var.quality)
    error_message = "quality must be 'low', 'medium', 'high', or 'ultra'"
  }
}
```

## Resources

```tf
resource "coder_script" "moonlight_setup" {
  agent_id     = var.agent_id
  display_name = "Setup Moonlight Streaming"
  icon         = local.icon
  run_on_start = true
  script       = var.os == "windows" ? 
    templatefile("${path.module}/scripts/install-moonlight.ps1", { 
      STREAMING_METHOD = var.streaming_method,
      PORT = var.port,
      QUALITY = var.quality
    }) : 
    templatefile("${path.module}/scripts/install-moonlight.sh", { 
      STREAMING_METHOD = var.streaming_method,
      PORT = var.port,
      QUALITY = var.quality
    })
}

resource "coder_app" "moonlight" {
  agent_id     = var.agent_id
  slug         = local.slug
  display_name = local.display_name
  url          = "moonlight://localhost"
  icon         = local.icon
  subdomain    = var.subdomain
  order        = var.order
  group        = var.group
}
```

## Testing Strategy

### Test Cases
1. **GPU Detection** - Verify NVIDIA GPU detection
2. **GameStream Setup** - Test NVIDIA GameStream configuration
3. **Sunshine Setup** - Test Sunshine server configuration
4. **Moonlight Client** - Test client installation and connection
5. **Cross-platform** - Test Windows and Linux compatibility
6. **Quality Settings** - Test different streaming quality options

### Test Commands
```bash
# Run tests
bun test

# Validate Terraform
terraform validate

# Test GPU detection
./scripts/detect-gpu.sh
```

## Demo Video Script

### Scene 1: Workspace Setup (30s)
- Show Coder dashboard
- Create workspace with GPU support
- Add Moonlight module configuration
- Deploy workspace

### Scene 2: GPU Detection (30s)
- Show GPU detection script running
- Display detected NVIDIA GPU
- Show automatic method selection

### Scene 3: Server Setup (45s)
- Show GameStream/Sunshine installation
- Display configuration process
- Show successful server startup

### Scene 4: Client Integration (30s)
- Show Moonlight app in Coder dashboard
- Demonstrate client connection
- Show streaming performance

### Scene 5: Functionality Demo (45s)
- Show low-latency streaming
- Demonstrate gaming performance
- Highlight key features

## Success Criteria

- ✅ **Automatic GPU detection** works correctly
- ✅ **GameStream/Sunshine** configures automatically
- ✅ **Moonlight client** connects successfully
- ✅ **Cross-platform** compatibility verified
- ✅ **Demo video** shows working functionality
- ✅ **All tests** pass successfully
- ✅ **Documentation** is comprehensive

## Timeline

- **Day 1**: Module structure and basic setup
- **Day 2**: GPU detection and server configuration
- **Day 3**: Client integration and testing
- **Day 4**: Documentation and demo video
- **Day 5**: PR creation and submission

## Bounty Claim

To claim the $200 bounty:
1. ✅ Implement all features successfully
2. ✅ Record demo video showing functionality
3. ✅ Create PR with `/claim #206` in description
4. ✅ Ensure high-quality implementation (no AI-generated code)
5. ✅ Follow all module guidelines

This implementation will provide a comprehensive Moonlight/GameStream solution that meets all bounty requirements and follows the same high-quality standards as the Parsec module. 