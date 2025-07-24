# RustDesk Coder Module

![RustDesk Logo](https://upload.wikimedia.org/wikipedia/commons/9/96/Rustdesk.svg)

This [Coder](https://coder.com) module installs and launches [RustDesk](https://rustdesk.com/) in your workspace, enabling remote desktop support from anywhere using a secure, peer-to-peer protocol.

> 📦 Automatically installs RustDesk (if not present) and launches it with a generated password.

---

## Features

- Installs RustDesk v1.4.0 if it's not already installed
- Generates a random 6-character password on start
- Outputs the RustDesk ID and password
- Automatically launches RustDesk on workspace start
- Provides an external app link to the [RustDesk web client](https://rustdesk.com/web)

---

## Usage

### Prerequisites

- Coder v2.5 or higher
- A workspace agent compatible with Linux and `apt` package manager

---

### Quickstart

1. Add the module to your [Coder Terraform workspace](https://registry.coder.com)
2. Include it in your `main.tf`:

```hcl
module "rustdesk" {
  source    = "github.com/your-username/your-module-repo"
  agent_id  = var.agent_id
}
