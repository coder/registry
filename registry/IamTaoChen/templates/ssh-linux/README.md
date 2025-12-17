---
display_name: Deploy Coder on existing Linux System
description: Provision an existing Linux system as a by deploying the Coder agent via SSH with this example template.
icon: "../../../../.icons/linux.svg"
verified: false
tags: ["linux"]
---

# Deploy Coder on existing Linux system

Provision an existing Linux system as a [Coder workspace](https://coder.com/docs/workspaces) by deploying the Coder agent via SSH with this example template.

## Prerequisites

### Authentication

This template assumes you have SSH access to the target Linux system. You can use either password-based authentication or an SSH private key. Ensure the target system allows SSH connections and has basic utilities like `bash` installed. The user account specified must have sufficient permissions to execute scripts and manage processes in their home directory.

For more details on SSH setup, consult your Linux distribution's documentation or standard SSH guides.

## Architecture

This template deploys the following:

- A Coder agent configured for Linux (amd64 architecture).
- Conditional parameters for SSH authentication (password or key).
- A selection of applications (e.g., VS Code Desktop, VS Code Web, Cursor) that can be enabled via multi-select.
- `null_resource` blocks to handle workspace start/stop:
  - On start: Connects via SSH, creates a cache directory, writes and executes the agent's init script in the background, and logs the process ID.
  - On stop: Connects via SSH, kills the agent process if running, and removes the cache directory.
- Optional modules for additional apps like `coder-login`, `cursor`, and `vscode-web`, which are provisioned only if selected and when the workspace starts.

This setup does not provision new infrastructure; it remotely deploys and manages the Coder agent on your existing Linux host. Files and configurations in the user's home directory persist across restarts, but the agent is stopped and cleaned up on workspace stop.

### Persistent Agent

The agent is ephemeral by design (started on workspace start, stopped on stop). If you need a persistently running agent, modify the template to remove the stop logic or run the agent manually on the host.

## Parameters

The template includes the following configurable parameters:

- **Host**: The remote hostname, IPv4, or IPv6 address of the Linux system (default: `192.168.1.1`). Must match the regex `^[a-zA-Z0-9:.%\\-]+$`.
- **Username**: The SSH username for connecting to the host (default: the workspace owner's name).
- **SSH Auth Type**: The authentication method—either "password" or "SSH Key" (default: "password").
- **SSH Password**: (Shown only if "password" is selected) The password for SSH login. Input is masked.
- **SSH Private Key**: (Shown only if "SSH Key" is selected) The private key for SSH login, provided as a textarea. Input is masked.
- **Port**: The SSH port on the remote host (default: `22`). Must be between 1 and 65535.
- **Apps**: A multi-select list of applications to include in the workspace (default: `["VS Code Desktop"]`). Options: "VS Code Desktop", "VS Code Web", "Cursor".

## Usage

1. Create a new workspace in Coder using this template.
2. Fill in the parameters with your Linux system's details.
3. Start the workspace—Coden will connect via SSH and deploy the agent.
4. Access the workspace through the Coder dashboard. Selected apps (e.g., VS Code) will be available.
5. On stop, the agent process is terminated and cleaned up.

## Troubleshooting

- **SSH Connection Issues**: Verify the host, port, username, and credentials. Check firewall rules and SSH server status on the target system. Review the debug log at `~/.coder/<workspace_id>/debug.log` on the remote host.
- **Agent Not Starting**: Inspect the log file at `~/.coder/<workspace_id>/coder.log` on the remote host for errors.
- **App Not Appearing**: Ensure the app is selected in parameters and the workspace is restarted if changes are made.
- **Validation Errors**: Parameters like host and port have built-in validations—ensure inputs match the requirements.

For more advanced customization, refer to the [Coder Terraform provider documentation](https://registry.terraform.io/providers/coder/coder/latest/docs).