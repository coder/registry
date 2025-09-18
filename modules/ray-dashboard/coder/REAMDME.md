# Ray Coder Module

This Coder module provides easy integration of Ray.io distributed computing framework into your Coder workspaces. It automatically sets up Ray with a dashboard interface and creates a dedicated Python virtual environment.

## Features

- 🚀 **Ray Dashboard**: Web-based interface for monitoring Ray clusters
- 🐍 **Python Virtual Environment**: Isolated environment with Ray and dependencies
- 📊 **Jupyter Integration**: Optional Jupyter kernel with Ray support
- ⚙️ **Customizable**: Configurable Ray extras, packages, and settings
- 🔧 **Auto-setup**: Automatic Ray installation and dashboard startup

## Usage

### Basic Usage

```hcl
module "ray" {
  source   = "registry.coder.com/modules/ray/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

