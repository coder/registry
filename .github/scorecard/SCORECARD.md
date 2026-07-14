# Coder Registry Module Scorecard

**100 pts** = **Universal criteria (75)** + **one track (25)**

Score each criterion as **0 / half / full**.

## Scoring rubric

### Universal criteria — 75 pts

| Criterion                                          |    Pts | Pass =                                                                                                                                                           |
| -------------------------------------------------- | -----: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Presentation & Onboarding**                      | **25** |                                                                                                                                                                  |
| Configuration-mode examples                        |     12 | If the module has many options, each major mode has a documented example with sensible defaults, for example provider choice, app vs headless                    |
| Coder-context framing                              |      8 | Explains what the module adds on top of Coder, names both Coder and the target tool, and shows where Coder fits in the flow                                      |
| Visual preview                                     |      5 | README includes an image, GIF, or video of the module in action                                                                                                  |
| **Credential Hygiene**                             | **20** |                                                                                                                                                                  |
| Secrets marked sensitive                           |     16 | Sensitive inputs are marked `sensitive = true`, and README examples avoid inline secrets                                                                         |
| Non-hardcoded auth path                            |      4 | If possible, README shows a path that avoids pasting raw keys into templates, for example ServiceAccount, IAM/OAuth/external auth, API key helper, or AI Gateway |
| **Restricted-Network Readiness** _(if applicable)_ | **20** |                                                                                                                                                                  |
| Mirrorable artifact source                         |     10 | Download or install URL is configurable so it can point to an internal mirror or artifact store instead of the public internet                                   |
| Bring-your-own binary                              |      6 | Download or install can be disabled entirely when the tool is already baked into the image                                                                       |
| Egress transparency                                |      4 | External endpoints are documented, plus notes for restricted or air-gapped environments                                                                          |
| **Engineering Quality**                            | **10** |                                                                                                                                                                  |
| Input quality                                      |      6 | Inputs have clear descriptions, sensible defaults, and `validation` where appropriate                                                                            |
| Test coverage                                      |      4 | Clear testing story, `.tftest.hcl` primarily covers business logic, TypeScript tests cover end-to-end behavior                                                   |

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

## Sample scorecards

### `coder/claude-code`

| Presentation & Onboarding | Agent Integration | Credential Hygiene | Restricted-Network Readiness | Engineering Quality |      Overall |
| ------------------------: | ----------------: | -----------------: | ---------------------------: | ------------------: | -----------: |
|               **20 / 25** |       **15 / 25** |        **12 / 20** |                   **8 / 20** |         **10 / 10** | **65 / 100** |

<details>
<summary><strong>Drilldown</strong></summary>

#### Presentation & Onboarding — 20 / 25

| Criterion                   | Max | Score | Notes                                                                                 |
| --------------------------- | --: | ----: | ------------------------------------------------------------------------------------- |
| Configuration-mode examples |  12 |    12 | Strong examples for API key, OAuth, AI Gateway, Bedrock, Vertex, and managed settings |
| Coder-context framing       |   8 |     8 | Clearly explains what the module adds on top of Coder                                 |
| Visual preview              |   5 |     0 | No image, GIF, or video in README                                                     |

#### Agent Integration — 15 / 25

| Criterion             | Max | Score | Notes                                                        |
| --------------------- | --: | ----: | ------------------------------------------------------------ |
| AI governance         |  10 |     5 | Strong AI Gateway support, no current Agent Firewall support |
| Dashboard entry point |   5 |     5 | README includes `coder_app` example                          |
| Session continuity    |   5 |     0 | No documented resume or persistence pattern                  |
| Managed configuration |   5 |     5 | Strong managed settings and MCP support                      |

#### Credential Hygiene — 12 / 20

| Criterion                | Max | Score | Notes                                                                   |
| ------------------------ | --: | ----: | ----------------------------------------------------------------------- |
| Secrets marked sensitive |  16 |     8 | Sensitive vars exist, but README still shows inline secrets in examples |
| Non-hardcoded auth path  |   4 |     4 | Documents OAuth and AI Gateway paths                                    |

#### Restricted-Network Readiness — 8 / 20

| Criterion                  | Max | Score | Notes                                                                    |
| -------------------------- | --: | ----: | ------------------------------------------------------------------------ |
| Mirrorable artifact source |  10 |     0 | Installer source is not configurable to use an internal mirror           |
| Bring-your-own binary      |   6 |     6 | Supports pre-baked binary path and disabling install                     |
| Egress transparency        |   4 |     2 | External calls are somewhat implied, but not clearly listed in one place |

#### Engineering Quality — 10 / 10

| Criterion     | Max | Score | Notes                                                                                   |
| ------------- | --: | ----: | --------------------------------------------------------------------------------------- |
| Input quality |   6 |     6 | Inputs are well-described, with defaults and validation                                 |
| Test coverage |   4 |     4 | `.tftest.hcl` covers plan-time rules, TypeScript tests cover end-to-end script behavior |

#### Overall — 65 / 100

</details>

### `coder/code-server`

| Presentation & Onboarding | IDE Integration | Credential Hygiene | Restricted-Network Readiness | Engineering Quality |      Overall |
| ------------------------: | --------------: | -----------------: | ---------------------------: | ------------------: | -----------: |
|               **25 / 25** |     **19 / 25** |        **16 / 20** |                   **3 / 20** |         **10 / 10** | **73 / 100** |

<details>
<summary><strong>Drilldown</strong></summary>

#### Presentation & Onboarding — 25 / 25

| Criterion                   | Max | Score | Notes                                                                                              |
| --------------------------- | --: | ----: | -------------------------------------------------------------------------------------------------- |
| Configuration-mode examples |  12 |    12 | Good examples for version pinning, extensions, settings, workspace vs folder, offline/cached modes |
| Coder-context framing       |   8 |     8 | Clearly explains code-server in a Coder workspace                                                  |
| Visual preview              |   5 |     5 | README includes a screenshot                                                                       |

#### IDE Integration — 19 / 25

| Criterion                                  | Max | Score | Notes                                                                                  |
| ------------------------------------------ | --: | ----: | -------------------------------------------------------------------------------------- |
| Dashboard entry point                      |   7 |     7 | Built-in `coder_app` with launch behavior controls                                     |
| Managed configuration                      |   6 |     6 | Supports user and machine settings                                                     |
| Configurable folder or workdir             |   6 |     6 | Supports both `folder` and `workspace`                                                 |
| Pre-installed extensions _(web IDEs only)_ |   6 |     0 | Supports extensions, but no documented private marketplace or enterprise-managed story |

#### Credential Hygiene — 16 / 20

| Criterion                | Max | Score | Notes                                       |
| ------------------------ | --: | ----: | ------------------------------------------- |
| Secrets marked sensitive |  16 |    16 | No secret inputs or secret-bearing examples |
| Non-hardcoded auth path  |   4 |     0 | No relevant auth-path guidance              |

#### Restricted-Network Readiness — 3 / 20

| Criterion                  | Max | Score | Notes                                                                                    |
| -------------------------- | --: | ----: | ---------------------------------------------------------------------------------------- |
| Mirrorable artifact source |  10 |     0 | Installer source is not configurable for an internal mirror                              |
| Bring-your-own binary      |   6 |     3 | Offline and cached modes help, but there is no first-class custom binary/source override |
| Egress transparency        |   4 |     0 | External endpoints are not clearly documented                                            |

#### Engineering Quality — 10 / 10

| Criterion     | Max | Score | Notes                                                                                                 |
| ------------- | --: | ----: | ----------------------------------------------------------------------------------------------------- |
| Input quality |   6 |     6 | Inputs are well-described, with defaults and validation                                               |
| Test coverage |   4 |     4 | `.tftest.hcl` covers plan-time rules, TypeScript tests cover script behavior and settings merge flows |

#### Overall — 73 / 100

</details>

### `coder/vscode-web`

| Presentation & Onboarding | IDE Integration | Credential Hygiene | Restricted-Network Readiness | Engineering Quality |      Overall |
| ------------------------: | --------------: | -----------------: | ---------------------------: | ------------------: | -----------: |
|               **25 / 25** |     **19 / 25** |        **16 / 20** |                   **0 / 20** |          **7 / 10** | **67 / 100** |

<details>
<summary><strong>Drilldown</strong></summary>

#### Presentation & Onboarding — 25 / 25

| Criterion                   | Max | Score | Notes                                                                                           |
| --------------------------- | --: | ----: | ----------------------------------------------------------------------------------------------- |
| Configuration-mode examples |  12 |    12 | Good examples for folder, workspace, extensions, settings, pinning, cached and offline behavior |
| Coder-context framing       |   8 |     8 | Clearly explains VS Code Web in a Coder workspace                                               |
| Visual preview              |   5 |     5 | README includes a GIF                                                                           |

#### IDE Integration — 19 / 25

| Criterion                                  | Max | Score | Notes                                                                                  |
| ------------------------------------------ | --: | ----: | -------------------------------------------------------------------------------------- |
| Dashboard entry point                      |   7 |     7 | Built-in `coder_app` with launch behavior controls                                     |
| Managed configuration                      |   6 |     6 | Supports machine settings and trust-related config                                     |
| Configurable folder or workdir             |   6 |     6 | Supports both `folder` and `workspace`                                                 |
| Pre-installed extensions _(web IDEs only)_ |   6 |     0 | Supports extensions, but no documented private marketplace or enterprise-managed story |

#### Credential Hygiene — 16 / 20

| Criterion                | Max | Score | Notes                                       |
| ------------------------ | --: | ----: | ------------------------------------------- |
| Secrets marked sensitive |  16 |    16 | No secret inputs or secret-bearing examples |
| Non-hardcoded auth path  |   4 |     0 | No relevant auth-path guidance              |

#### Restricted-Network Readiness — 0 / 20

| Criterion                  | Max | Score | Notes                                                                                              |
| -------------------------- | --: | ----: | -------------------------------------------------------------------------------------------------- |
| Mirrorable artifact source |  10 |     0 | Download source is not configurable for an internal mirror                                         |
| Bring-your-own binary      |   6 |     0 | Offline and cached behavior exist, but no documented bring-your-own binary or custom artifact path |
| Egress transparency        |   4 |     0 | External endpoints are not clearly documented                                                      |

#### Engineering Quality — 7 / 10

| Criterion     | Max | Score | Notes                                                                                                         |
| ------------- | --: | ----: | ------------------------------------------------------------------------------------------------------------- |
| Input quality |   6 |     3 | Inputs are mostly well-described, but some validation and polish are less complete than the strongest modules |
| Test coverage |   4 |     4 | `.tftest.hcl` covers plan-time rules, TypeScript tests cover script behavior and settings merge flows         |

#### Overall — 67 / 100

</details>

### `coder/git-clone` (Utility)

Utility module: no track section. Restricted-Network Readiness is not applicable, the module downloads nothing and clones a caller-controlled URL. Denominator is 55, normalized to 100.

| Presentation & Onboarding | Credential Hygiene | Restricted-Network Readiness | Engineering Quality |      Overall |
| ------------------------: | -----------------: | ---------------------------: | ------------------: | -----------: |
|               **20 / 25** |        **20 / 20** |                          N/A |          **8 / 10** | **87 / 100** |

<details>
<summary><strong>Drilldown</strong></summary>

#### Presentation & Onboarding — 20 / 25

| Criterion                   | Max | Score | Notes                                                                                        |
| --------------------------- | --: | ----: | -------------------------------------------------------------------------------------------- |
| Configuration-mode examples |  12 |    12 | Examples for custom path, branch clones, GitHub/GitLab, self-hosted providers, external auth |
| Coder-context framing       |   8 |     8 | Clearly explains cloning into a Coder workspace and composing with other modules             |
| Visual preview              |   5 |     0 | No image, GIF, or video in README                                                            |

#### Credential Hygiene — 20 / 20

| Criterion                | Max | Score | Notes                                                                            |
| ------------------------ | --: | ----: | -------------------------------------------------------------------------------- |
| Secrets marked sensitive |  16 |    16 | No secret inputs or secret-bearing examples                                      |
| Non-hardcoded auth path  |   4 |     4 | Documents Coder external auth (`coder_external_auth`) instead of embedded tokens |

#### Restricted-Network Readiness — N/A

| Criterion                  | Max | Score | Notes                                                                  |
| -------------------------- | --: | ----: | ---------------------------------------------------------------------- |
| Mirrorable artifact source |   — |   N/A | Clone URL is fully caller-controlled, nothing to mirror                |
| Bring-your-own binary      |   — |   N/A | Module downloads nothing; relies on `git` already present in the image |
| Egress transparency        |   — |   N/A | Only contacts the URL the caller provides                              |

#### Engineering Quality — 8 / 10

| Criterion     | Max | Score | Notes                                                                      |
| ------------- | --: | ----: | -------------------------------------------------------------------------- |
| Input quality |   6 |     6 | Inputs are well-described with sensible defaults                           |
| Test coverage |   4 |     2 | Has TypeScript end-to-end tests, but no `.tftest.hcl` business-logic tests |

#### Overall — 87 / 100

Raw 48 / 55 → `round(48 / 55 × 100)` = **87**

</details>
