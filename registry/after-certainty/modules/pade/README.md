---
display_name: PADE
description: Install the PADE CLI and bind a workspace to an existing PADE broker using runtime workload identity
icon: ../../../../.icons/pade.svg
verified: false
tags: [helper, integration, identity, security]
---

# PADE

Installs the [PADE](https://github.com/After-Certainty/pade) CLI in a Coder workspace and writes broker-only capability bindings, so tools in the workspace can resolve explicitly configured capabilities through an existing PADE broker without durable provider credentials.

```tf
module "pade" {
  source              = "registry.coder.com/after-certainty/pade/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  broker_endpoint     = "https://pade-broker.example.com"
  broker_capabilities = ["github.repo.read"]
}
```

Before publication to the Registry, the module can be consumed directly from Git:

```tf
module "pade" {
  source              = "git::https://github.com/After-Certainty/pade-coder.git//modules/pade"
  agent_id            = coder_agent.main.id
  broker_endpoint     = "https://pade-broker.example.com"
  broker_capabilities = ["github.repo.read"]
}
```

## What it does

On workspace start, the module:

1. downloads the released PADE CLI for the workspace architecture;
2. verifies the archive against the release `SHA256SUMS`;
3. installs `pade` to `~/.local/bin`;
4. writes `~/.config/pade/coder-bindings.yaml` (mode `0600`) containing only the capabilities listed in `broker_capabilities`;
5. adds `~/.local/bin` to `PATH` and sets `PADE_BINDINGS` in normal shell startup files;
6. runs `pade --version` to confirm the install.

Coder script lifecycle, synchronization, and logs are handled by `coder-utils`. It materializes the installer at `~/.coder-modules/after-certainty/pade/scripts/install.sh` and writes its output to `~/.coder-modules/after-certainty/pade/logs/install.log`. PADE's binary and bindings retain their tool-specific locations.

Unlike the previous direct startup script, `coder-utils` does not block login while installation runs. Wait for the PADE install script to finish before using `pade`. Dependent Coder scripts can use `coder exp sync want <self> ${join(" ", module.pade.scripts)}` to wait for the install pipeline.

Persistent home storage keeps the binary and bindings between starts; ephemeral home storage simply causes them to be recreated.

It does not deploy a PADE broker, define broker-side authorization, or place provider credentials in the workspace or in Terraform state. The bindings file contains only the broker endpoint, audience, identity adapter, and capability names.

`coder-utils` also reads Coder workspace-owner metadata. Its Terraform data-source state can include existing Coder control-plane credentials supplied by the runtime; these are not passed to PADE or used as workload identity. Keep Terraform state protected as for the parent Coder template.

The module-managed bindings file is separate from PADE's default `~/.config/pade/bindings.yaml`, so user-managed bindings are not overwritten.

## Dynamic capabilities: trusted downstream bindings

`broker_capabilities` is optional. When supplied, its static capability names are rendered into broker-only bindings exactly as before. When omitted or set to `[]`, the module installs PADE with an **empty capability map**; demand alone never grants authority.

The module exposes three generic integration outputs:

- `bindings_path`: module-managed `~/.config/pade/coder-bindings.yaml` file (expand `~` to the workspace user's home in filesystem operations).
- `broker_binding`: non-secret, operator-configured `provider: broker` template with endpoint, audience, and runtime identity adapter. It is _not_ an authorization grant.
- `scripts`: Coder synchronization names. A dependent Coder script can use `coder exp sync want <self> ${join(" ", module.pade.scripts)}` to wait until PADE installation has finished.

A Coder template may omit the static capabilities:

```tf
module "pade" {
  source          = "git::https://github.com/After-Certainty/pade-coder.git//modules/pade"
  agent_id        = coder_agent.main.id
  broker_endpoint = var.pade_broker_endpoint
}
```

A separately owned **trusted downstream integration** should verify or validate its input, apply operator-controlled support and mapping policy, and construct a complete PADE `version: "0.1"` YAML file with `capabilities` containing only approved, mapped capability names. Each resulting value can use `module.pade.broker_binding`. The downstream integration must atomically replace `module.pade.bindings_path` with file mode `0600` **after** the PADE installer completes and **before** dependent PADE workloads start. Do not merge against previous mappings or generate trusted bindings directly from unverified repository content. Missing validation, unsupported demand, failed generation, or failed writing must leave the workspace without usable bindings.

In dynamic mode, PADE's installer writes the empty map before any network download and again after installation, removing stale bindings even if a subsequent download fails. It intentionally does **not** install `rc-pade` or interpret Runtime Conditions; that belongs in an optional downstream Coder integration. The local file is workspace-user-writable, not a security isolation boundary. The broker still authenticates and authorizes each request; runtime isolation and downstream IAM are separate responsibilities.

Existing static templates remain compatible. This change does not alter PADE's protocol, broker policy, workload identity, or provider authority.

## Prerequisites

- A Linux workspace with `curl`, `tar`, `sha256sum`, `base64`, `awk`, and `find`.
- An existing PADE broker reachable over HTTPS that authorizes the workspace's workload identity.
- A workspace runtime that provides the selected workload identity (for `gce`, the GCE metadata server with an attached service account).

## Proven vs. accepted

The module accepts every value the current PADE Consumer supports, but only one path has been validated end to end through this module:

| Dimension           | Proven through this module               | Accepted, not yet validated here |
| ------------------- | ---------------------------------------- | -------------------------------- |
| Workload identity   | `gce` (GCE metadata)                     | `cursor`                         |
| Workspace OS / arch | Linux `amd64`                            | Linux `arm64`                    |
| PADE version        | `v0.3.0` (live); `v0.4.1` (installer CI) | v0.4.1 live broker validation    |
| Capability          | `github.repo.read`                       | other broker-authorized names    |

Accepting `broker_identity = "cursor"` reflects what PADE supports; it does not mean a Cursor-on-Coder path has been validated.

## PADE v0.4.1 upgrade validation

See [the GCE v0.4.1 follow-up runbook](https://github.com/After-Certainty/pade-coder/blob/main/experiments/001-gce-broker/v041-followup.md) for Coder template update steps, a version-gated authenticated smoke, and evidence hygiene.

The module's **default** PADE release is v0.4.1. Existing templates that explicitly
set `pade_version = "v0.3.0"` or `"v0.4.0"` remain pinned until the template
owner changes that input. This module does not automatically update running
workspaces or reconfigure Cloud Run.

After updating the Coder template and the GCE-backed workspace, run the
existing manual smoke test from a fresh Coder workspace shell:

```bash
pade --version
PADE_CODER_EXPECTED_VERSION=v0.4.1 bash experiments/001-gce-broker/run.sh
```

The script checks GCE metadata workload identity and broker-mediated
`github.repo.read` against the configured endpoint. Do not log ID tokens
or provider credentials. Record any new v0.4.1 result separately from the
original 2026-10-06 Experiment 001 evidence. GitHub Actions tests installation
and Terraform bindings only; it has no authenticated GCE workload identity.

## Identity boundary

```text
Coder workspace (e.g. on GCE)
       |
       | runtime workload identity (GCE metadata)
       v
PADE Consumer  ------------->  PADE broker
```

Coder owns the workspace lifecycle. The underlying runtime supplies workload identity. The module does not treat Coder control-plane authentication as PADE identity.

## Examples

### Explicit broker audience

```tf
module "pade" {
  source              = "registry.coder.com/after-certainty/pade/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  pade_version        = "v0.4.1"
  broker_endpoint     = "https://pade-broker.example.com"
  broker_audience     = "pade-broker"
  broker_identity     = "gce"
  broker_capabilities = ["github.repo.read"]
}
```

### Using the bindings

New shells pick up `PADE_BINDINGS` automatically. Processes that do not source shell startup files can set `PADE_BINDINGS` to the `bindings_path` output or pass that path to `pade` with `--bindings`.

## Workload identity and credential exposure

`broker_capabilities` creates local resolution configuration, not an authorization
grant. The broker verifies the runtime assertion and applies server-owned policy
on every request. Selecting `gce` or `cursor` chooses how the Consumer obtains
identity; it does not translate Coder user identity into a PADE subject.

GCE workspaces using the same attached service account share the same broker
subject and its allowed capabilities. Coder workspace-owner metadata and RC
provenance do not create per-user isolation. Use distinct runtime identities and
explicit broker policy when that separation is required. The module does not
restrict access to the GCE metadata server or another runtime's identity socket.

A child receiving credential material can read it and pass it to descendants.
A copied credential can remain usable after `pade exec` or a workspace ends,
subject to downstream expiry/revocation. Output redaction is best effort, not a
sandbox. Reusing a valid workload assertion can obtain fresh material while
server policy allows it. Keep bootstrap authority off the workspace and scope
issued authority in downstream IAM.

These boundaries were reviewed at pade-coder
`3805842e6d8b65a9c8993def2ec45349fe8a0639` (2026-10-09), alongside the PADE
`docs/security/2026-10-boundary-investigation.md` report. This documentation change
adds no new identity adapter, grant semantics, or runtime behavior. Existing
module tests cover supported/unsupported identity selection and broker-only
bindings; live Coder/GCE validation was not repeated for this review.
