---
display_name: Gemini CLI
description: A Docker workspace template with Gemini CLI for AI-powered coding assistance
icon: ../../../../.icons/gemini.svg
verified: false
tags: [docker, gemini, ai, google, node]
---

# Gemini CLI Template

A Docker workspace template that integrates Google's Gemini CLI for AI-powered coding assistance using the official [coder-labs/gemini](https://registry.coder.com/modules/coder-labs/gemini) module.

## Features

- **Docker-based**: Lightweight Docker container with persistent storage
- **Official Gemini Module**: Uses the verified `coder-labs/gemini` module v1.0.0 from Coder registry
- **Node.js Environment**: Pre-configured Node.js development environment
- **Code Server**: VS Code in the browser for development
- **Secure API Key Management**: Parameter for Gemini API key
- **Terminal Access**: Direct terminal access for manual Gemini CLI usage
- **AgentAPI Integration**: Includes web UI and task automation capabilities

## Prerequisites

- Docker environment with Coder deployed
- Gemini API key from Google AI Studio

## Parameters

### GEMINI_API_KEY (Required)

- **Type**: String
- **Description**: Your Gemini API key for accessing Google's AI models
- **Mutable**: Yes

Get your API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Usage

### Interactive Mode

1. Open the Terminal app in your workspace
2. Run `gemini` to start an interactive session with Google's AI
3. Ask questions or request coding assistance

### Web UI Mode

The module includes AgentAPI which provides a web interface for Gemini:

1. Look for the Gemini app in your workspace
2. Click to open the web-based interface
3. Interact with Gemini through the browser

### Example Commands

```bash
# Interactive chat with Gemini
gemini

# Generate code with a specific prompt
echo "Create a simple Express.js server" | gemini

# Get help with debugging
echo "Explain this error: TypeError: Cannot read property 'length' of undefined" | gemini
```

## What's Included

- **Docker Container**: `codercom/enterprise-node:ubuntu` with Node.js pre-installed
- **Gemini CLI**: Installed and configured via the official `coder-labs/gemini` module
- **AgentAPI**: Web interface for Gemini interaction and task automation
- **Code Server**: VS Code in the browser for development
- **Terminal**: Direct shell access
- **Persistent Storage**: Home directory persisted across workspace restarts

## Module Details

This template uses the official [`coder-labs/gemini`](https://registry.coder.com/modules/coder-labs/gemini) module v1.0.0 which provides:

- Automatic Gemini CLI installation and configuration
- AgentAPI web interface for browser-based interaction
- Proper environment variable setup
- Integration with Coder's agent system
- Support for multiple Gemini AI models

> **Note**: We use version 1.0.0 specifically because newer versions (1.1.0+) have validation issues in their agentapi dependency that prevent `terraform init` from working.

## Security

- API keys are managed through Coder parameters
- Container runs with appropriate user permissions
- Network isolation through Docker

## Resources

- **Base Image**: `codercom/enterprise-node:ubuntu`
- **Storage**: Persistent Docker volume for `/home/coder`
- **Network**: Docker bridge with host gateway access

## Troubleshooting

### Gemini CLI Not Found

The official module handles Gemini CLI installation automatically. If you encounter issues, check the startup logs in the agent.

### API Key Issues

Ensure your Gemini API key is valid and has the necessary permissions. You can test it manually by running:

```bash
export GEMINI_API_KEY="your-key-here"
gemini "Hello, can you help me?"
```

### Module Issues

If you encounter issues with the `coder-labs/gemini` module, refer to the [module documentation](https://registry.coder.com/modules/coder-labs/gemini) for troubleshooting steps.

### Version Compatibility

This template uses gemini module v1.0.0 due to validation issues in newer versions. If these issues are resolved in future versions, the template can be updated to use the latest version.

## Support

For issues with this template, please contact the template maintainer or file an issue in the Coder registry repository.
