---
name: Skills deploy gate failed
about: Auto-opened by the deploy-registry verify job when catalogue or scan fails.
title: "[skills-gate] Catalogue or scan failure blocking deploy"
labels: ["skills-gate"]
---

The pre-deploy verify job for the agent-skills catalogue failed.
Most recent run:

{{ env.WORKFLOW_URL }}

Trigger: `{{ env.RUN_TRIGGER }}`

This is a single rolling tracker issue. The deploy workflow updates the
same open issue on every subsequent failure until it is closed. Closing
this issue without fixing the underlying problem reopens (or creates)
the next time the gate fails.

Likely causes:

- A `sources[].skills[<slug>]` override in `registry/<namespace>/skills/README.md`
  no longer matches a `skills/<slug>/SKILL.md` upstream (renamed,
  deleted, or moved).
- A declared `owner/repo@ref` no longer clones (repo renamed, deleted,
  flipped to private, or the branch ref is gone).
- An upstream `SKILL.md` is missing the required `name` or `description`
  frontmatter per the agentskills.io v0.2.0 specification.
- A SkillSpector critical-severity finding on upstream content. Open
  alerts are listed under the repository's Security tab, Code scanning.

See the run logs and any new Code scanning alerts for specifics, then
land a PR that updates the catalogue or the upstream source repo.
