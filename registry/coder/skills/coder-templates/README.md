---
display_name: Coder Templates Skill
description: Agent skill for creating and updating Coder Registry workspace templates
icon: ../../../../.icons/coder.svg
tags: [skill, templates, terraform]
---

# Coder Templates Skill

An [Agent Skill](https://agentskills.io) for creating and updating Coder Registry workspace templates with agent setup, infrastructure provisioning, and module consumption.

## Install

Install via the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add https://registry.coder.com
```

Or add directly to your agent's skills directory:

```bash
npx skills add https://registry.coder.com --name coder-templates
```

## What This Skill Covers

- Scaffolding new templates with `new_template.sh`
- Infrastructure provisioning patterns (Docker, AWS, GCP, Azure, Kubernetes)
- Agent setup and module consumption
- Workspace parameters, presets, and prebuilds
- Task-oriented template configuration
- README frontmatter and content conventions
- Icon handling and testing workflows

## Links

- [Coder Registry](https://registry.coder.com)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Coder Registry Contributing Guide](https://github.com/coder/registry/blob/main/CONTRIBUTING.md)
