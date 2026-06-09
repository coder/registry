---
display_name: Deploy Coder on existing Linux System
description: Provision an existing Linux system as a workspace by deploying the Coder agent via SSH with this example template.
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

## Security Considerations

Warning: This template stores SSH credentials (password or private key) in the Terraform state file and passes them as environment variables during deployment. In production environments, this can introduce security risks, as the state file contains sensitive information in plain text and may be accessible if not properly secured.

## Usage

1. Create a new workspace in Coder using this template.
2. Fill in the parameters with your Linux system's details.
3. Start the workspace—Coder will connect via SSH and deploy the agent.
4. Access the workspace through the Coder dashboard. Selected apps (e.g., VS Code) will be available.
5. On stop, the agent process is terminated and cleaned up.

## Troubleshooting

- **SSH Connection Issues**: Verify the host, port, username, and credentials. Check firewall rules and SSH server status on the target system. Review the debug log at `~/.coder/<workspace_id>/debug.log` on the remote host.
- **Agent Not Starting**: Inspect the log file at `~/.coder/<workspace_id>/coder.log` on the remote host for errors.
- **App Not Appearing**: Ensure the app is selected in parameters and the workspace is restarted if changes are made.
- **Validation Errors**: Parameters like host and port have built-in validations—ensure inputs match the requirements.

For more advanced customization, refer to the [Coder Terraform provider documentation](https://registry.terraform.io/providers/coder/coder/latest/docs).
