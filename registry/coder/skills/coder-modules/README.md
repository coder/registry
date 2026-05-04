---
display_name: Coder Modules Skill
description: Agent skill for creating and updating Coder Registry modules
icon: ../../../../.icons/coder.svg
tags: [skill, modules, terraform]
---

# Coder Modules Skill

An [Agent Skill](https://agentskills.io) for creating and updating Coder Registry modules with proper scaffolding, Terraform testing, README frontmatter, and version management.

## Install

Install via the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add https://registry.coder.com
```

Or add directly to your agent's skills directory:

```bash
npx skills add https://registry.coder.com --name coder-modules
```

## What This Skill Covers

- Scaffolding new modules with `new_module.sh`
- Terraform resource patterns (`coder_app`, `coder_script`, `coder_env`, etc.)
- README frontmatter and content conventions
- Testing with `.tftest.hcl` and `main.test.ts`
- Script organization patterns (root `run.sh`, `scripts/` directory, inline)
- Icon handling and version management
- Variable conventions and module composition

## Links

- [Coder Registry](https://registry.coder.com)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Coder Registry Contributing Guide](https://github.com/coder/registry/blob/main/CONTRIBUTING.md)
