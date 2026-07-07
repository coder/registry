---
icon: ../../../.icons/coder.svg
sources:
  - repo: coder/skills@main
    skills:
      setup:
        display_name: Coder Setup
        icon: ../../../.icons/coder.svg
        tags: [coder, deployment, configuration]
      modules:
        display_name: Coder Modules
        icon: ../../../.icons/coder-modules.svg
        tags: [coder, terraform, modules]
      templates:
        display_name: Coder Templates
        icon: ../../../.icons/coder-templates.svg
        tags: [coder, terraform, templates]
---

# Coder Skills

Agent skills maintained by [Coder](https://coder.com) for installing,
configuring, and developing with the Coder platform.

Skills are sourced from [coder/skills](https://github.com/coder/skills)
and served through the registry's API, MCP tools, and
[well-known discovery endpoint](https://agentskills.io/specification).

## Available Skills

| Skill                                                                | Description                                                                                                                                                                                   |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Coder Setup](https://registry.coder.com/skills/coder/setup)         | Install, deploy, or bootstrap a new Coder deployment end-to-end. Covers Docker, Kubernetes/Helm, VM, cloud, HTTPS/domain setup, first admin creation, starter templates, and first workspace. |
| [Coder Modules](https://registry.coder.com/skills/coder/modules)     | Add or update Coder modules (from registry.coder.com/modules) inside an existing Coder template. Covers IDEs, AI agents, secrets, dev environment tools, and cloud regions.                   |
| [Coder Templates](https://registry.coder.com/skills/coder/templates) | Author, edit, push, or version a Coder template. Covers starter selection, template anatomy, parameters, validation, push, and first-workspace verification.                                  |
