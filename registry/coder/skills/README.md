---
icon: ../../../.icons/coder.svg
sources:
  - repo: coder/skills@main
    skills:
      setup:
        display_name: Setup & Configuration
        icon: ../../../.icons/coder.svg
        tags: [coder, deployment, configuration]
---

# Coder Skills

Agent skills maintained by [Coder](https://coder.com) for installing,
configuring, and developing with the Coder platform.

Skills are sourced from [coder/skills](https://github.com/coder/skills)
and served through the registry's API, MCP tools, and
[well-known discovery endpoint](https://agentskills.io/specification).

## Install

Install directly from the source repo:

```bash
# Install a specific skill
npx skills add coder/skills@setup

# Install all Coder skills
npx skills add coder/skills
```

Or install from the registry:

```bash
npx skills add https://registry.coder.com
```

## Available Skills

Skills are discovered automatically from the source repo at build time.
Browse the full list at [registry.coder.com/skills](https://registry.coder.com/skills).
