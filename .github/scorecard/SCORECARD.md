# Coder Registry Module Scorecard

**100 pts** = **Universal criteria (75)** + **one track (25)**

Score each criterion as **0 / half / full**.

## Scoring rubric

### Universal criteria — 75 pts

| Criterion                                              |    Pts | Pass =                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------ | -----: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Presentation & Onboarding**                          | **25** |                                                                                                                                                                                                                                                                                                 |
| Configuration-mode examples                            |     12 | If the module has many options, each major mode has a documented example with sensible defaults, for example provider choice, app vs headless                                                                                                                                                   |
| Coder-context framing                                  |      8 | Explains what the module adds on top of Coder, names both Coder and the target tool, and shows where Coder fits in the flow                                                                                                                                                                     |
| Visual preview                                         |      5 | README includes an image, GIF, or video of the module in action                                                                                                                                                                                                                                 |
| **Credential Hygiene**                                 | **20** |                                                                                                                                                                                                                                                                                                 |
| Secrets marked sensitive                               |     16 | Sensitive inputs are marked `sensitive = true`, and README examples avoid inline secrets                                                                                                                                                                                                        |
| Non-hardcoded auth path                                |      4 | If possible, README shows a path that avoids pasting raw keys into templates, for example ServiceAccount, IAM/OAuth/external auth, API key helper, or AI Gateway                                                                                                                                |
| **Restricted-Environment Readiness** _(if applicable)_ | **20** |                                                                                                                                                                                                                                                                                                 |
| Mirrorable artifact source                             |     10 | A module input variable overrides the URL the tool itself is downloaded or installed from, so it can point to an internal mirror or artifact store. Variables for auxiliary config URLs do not count, and neither do workarounds outside the module such as transparent proxies or DNS rewrites |
| Bring-your-own binary                                  |      5 | A documented way to disable download or install entirely when the tool is already baked into the image                                                                                                                                                                                          |
| Egress transparency                                    |      3 | A dedicated README section enumerates the external endpoints contacted at install and runtime, with notes for restricted or air-gapped environments. Mentions scattered across unrelated examples earn at most half; inferable endpoints do not count                                           |
| Runs without sudo                                      |      2 | Install and runtime scripts work as an unprivileged user, or the README documents the no-sudo path. Scripts that require root for core functionality score 0; sudo needed only for optional features with a working fallback earns half                                                         |
| **Engineering Quality**                                | **10** |                                                                                                                                                                                                                                                                                                 |
| Input quality                                          |      6 | Inputs have clear descriptions, sensible defaults, and `validation` where appropriate                                                                                                                                                                                                           |
| Test coverage                                          |      4 | Clear testing story, `.tftest.hcl` primarily covers business logic, TypeScript tests cover end-to-end behavior                                                                                                                                                                                  |

### Agent track — 25 pts

| Criterion             | Pts | Pass =                                                                                                                                                                                                    |
| --------------------- | --: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI governance         |  10 | Documented support for Coder AI Gateway and/or Agent Firewall, including how Coder governs auth, routing, or policy enforcement for the agent                                                             |
| Dashboard entry point |   5 | Documented `coder_app` support, built-in or example                                                                                                                                                       |
| Session continuity    |   5 | Documented support for continuing an existing agent session across reconnects or relaunches, either through native resume/session ID support or a persistent session manager such as boo, tmux, or screen |
| Managed configuration |   5 | Documented support for managed MCP, settings, policies, or workdir config                                                                                                                                 |

### IDE track — 25 pts

| Criterion                                  | Pts | Pass =                                                                       |
| ------------------------------------------ | --: | ---------------------------------------------------------------------------- |
| Dashboard entry point                      |   7 | `coder_app` support with proper launch behavior                              |
| Managed configuration                      |   6 | Documented support for managed IDE settings or config                        |
| Configurable folder or workdir             |   6 | Documented support for opening or starting in a configured folder or workdir |
| Pre-installed extensions _(web IDEs only)_ |   6 | For web IDEs, documented support for pre-installing extensions               |

### Utility track

Utility modules are scored on Universal criteria only, then normalized:

`round(raw / 75 * 100)`

## Notes

| Topic                    | Rule                                                                                                                                                                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Track assignment         | Every score should record which track was used                                                                                                                                                                                                 |
| Internal building blocks | Modules whose README cautions against direct use (for example "we do not recommend using this module directly") are excluded from scoring entirely                                                                                             |
| If applicable            | Criteria or themes marked _if applicable_ are excluded when the concern does not exist by construction, for example a module that downloads nothing. Excluded points are removed from the denominator and the final score is normalized to 100 |
| N/A handling             | Outside _if applicable_ criteria, missing support scores zero. Only Utility modules skip the track section                                                                                                                                     |
| Scoring                  | Full = implemented and documented; half = partial, awkward, or under-documented; zero = absent                                                                                                                                                 |

## Grading

|  Score | Badge      |
| -----: | ---------- |
| 90-100 | Exemplary  |
|  75-89 | Strong     |
|  50-74 | Adequate   |
|    <50 | Needs work |

## Output format

Every scorecard leads with a theme-level summary table, then a collapsed
drilldown with per-criterion tables grouped by theme.

## Live scorecards

Every scored module is listed in the pinned
[📊 Module Scorecards](https://github.com/coder/registry/discussions/1011)
discussion, which links each module's dedicated scorecard discussion.
