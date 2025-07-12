---
display_name: "Hetzner Cloud Template"
description: "A complete Coder template to provision Hetzner Cloud virtual machines with private networking and attached volumes."
icon: "../../../../.icons/Hetzner.svg"
verified: false
tags: ["hetzner", "cloud", "vm", "infrastructure"]
---

# Hetzner Cloud Template

This template provisions one or more Hetzner Cloud virtual machines with:
- Private network
- Attached volumes
- Coder agent

It is designed to be used directly by Coder to spin up full workspaces on Hetzner Cloud.

##  Requirements
- Hetzner Cloud account
- Hetzner Cloud API token (can be added via environment variable or Terraform variable)

##  Usage

To test this template:

```sh
coder templates push hetzner-cloud -d .
```