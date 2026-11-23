---
display_name: OpenCode Server
description: Run OpenCode 1.x as a password-protected headless server and attach to it from your laptop or the browser.
icon: ../../../../.icons/opencode.svg
verified: false
tags: [agent, opencode, ai, server, ai-gateway]
---

# OpenCode Server

Runs [OpenCode](https://opencode.ai) 1.x in [server mode](https://opencode.ai/docs/server/) (`opencode serve`) inside the workspace, so the agent, its sessions, and its tools live next to your code while you drive it from a local terminal with `opencode attach`.

```tf
module "opencode_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/opencode-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/src"
}
```

- Installs OpenCode 1.x with the official installer (skipped if the requested version is already installed).
- Starts `opencode serve` on `127.0.0.1:4096` with HTTP basic auth. The password is generated once and stored in `~/.config/opencode/server-password`.
- Adds an **OpenCode** terminal app that attaches to the same server, so browser and laptop clients share sessions.
- Sets `OPENCODE_DISABLE_AUTOUPDATE` so the installed version only changes when you change the template.

This module targets OpenCode 1.x. For OpenCode 2, use [`coder-labs/opencode`](https://registry.coder.com/modules/coder-labs/opencode).

## Connect from your laptop

Install an OpenCode 1.x client locally, then:

```sh
WORKSPACE=my-workspace
coder port-forward "$WORKSPACE" --tcp 4096:4096 &
export OPENCODE_SERVER_PASSWORD="$(coder ssh "$WORKSPACE" -- cat .config/opencode/server-password)"
opencode attach http://127.0.0.1:4096 --dir /home/coder/src
```

Sessions live in the server, so closing the app or the laptop client and attaching again picks up where you left off.

## AI governance

Coder can govern how OpenCode authenticates, where its model traffic goes, and which network destinations its tools can reach.

### AI Gateway

[AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) is a Premium Coder feature that proxies LLM traffic centrally. Set `enable_ai_gateway = true` to route OpenCode's `anthropic` and `openai` providers through your deployment:

- The install script writes an `opencode.json` whose provider `baseURL`s point at `<access_url>/api/v2/ai-gateway/anthropic/v1` and `<access_url>/api/v2/ai-gateway/openai/v1`. An existing `opencode.json` is left alone.
- The provider `apiKey` is the workspace owner's Coder session token. It reaches OpenCode through the `OPENCODE_SERVER_AI_GATEWAY_TOKEN` environment variable (an `{env:...}` placeholder in the config) and is never written to disk.

Developers never handle a provider key: the gateway holds the upstream credentials, authenticates each request as the workspace owner, and attributes and audits it.

```tf
module "opencode_server" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/droopy4096/opencode-server/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/src"
  enable_ai_gateway = true
}
```

### Agent Firewall

[Agent Firewall](https://coder.com/docs/ai-coder/agent-firewall) enforces a network egress allowlist. OpenCode runs tools and model calls inside `opencode serve`, not in the attach client, so this module puts the firewall around the server. Pass the outputs of the [`agent-firewall`](https://registry.coder.com/modules/coder/agent-firewall) module:

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.4"
  agent_id = coder_agent.main.id
}

module "opencode_server" {
  count                       = data.coder_workspace.me.start_count
  source                      = "registry.coder.com/droopy4096/opencode-server/coder"
  version                     = "1.0.0"
  agent_id                    = coder_agent.main.id
  workdir                     = "/home/coder/src"
  enable_ai_gateway           = true
  agent_firewall_wrapper_path = module.agent-firewall.agent_firewall_wrapper_path
  agent_firewall_config_path  = module.agent-firewall.agent_firewall_config_path
}
```

- The start script waits up to 5 minutes for the wrapper and refuses to start OpenCode without it.
- The server runs with `--jail-type=landjail` (Landlock). The default `nsjail` jail gives the server its own network namespace, so `opencode attach` and port forwarding could not reach it. Landlock needs a kernel with Landlock network rules (Linux 6.7 or later).
- Every process the server spawns inherits the jail: allowlisted HTTPS works, other destinations get `403`, and direct connections that skip the proxy fail.
- The firewall's proxy listens on port `8080` by default. Set `proxy_port` in the firewall config if something else in the workspace uses that port or another agent runs inside its own firewall.
- Add the hosts from [Network access](#network-access-and-air-gapped-environments) that you want OpenCode to reach to the allowlist. With AI Gateway, the deployment domain (added by the `agent-firewall` module) covers model traffic.

## Image requirements

The scripts need `bash`, `curl`, `tar` and `gzip` (and `unzip` for a `.zip` `binary_url`), and neither uses sudo. Debian, Ubuntu and Red Hat UBI 9 (`ubi9/ubi`) images work as they are. `ubi9/ubi-minimal` lacks `tar` and `gzip`; add them with `microdnf install -y tar gzip`.

### Alpine and other musl images

OpenCode publishes separate builds for musl libc, and they link against the C++ runtime, which bare Alpine doesn't include. Add these packages to the image:

```dockerfile
RUN apk add --no-cache bash curl libgcc libstdc++
```

The module detects musl on its own: the official installer and a `binary_url` that uses `{target}` both pick the `-musl` build. If `opencode --version` fails on a musl system, the install script names the missing packages. A binary from `opencode_bin` or the image must also be a musl build.

## Network access and air-gapped environments

| When    | Endpoint                                                         | Purpose                                       | How to avoid it                                        |
| ------- | ---------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------ |
| Install | `opencode.ai/install` (`install_url`)                            | Installer script                              | `binary_url` or `install_opencode = false`             |
| Install | `github.com/anomalyco/opencode/releases`                         | Release archive downloaded by the installer   | `binary_url` or `install_opencode = false`             |
| Install | `registry.npmjs.org`, `api.github.com`                           | Latest 1.x version lookup when none is pinned | Set `opencode_version`                                 |
| Runtime | `models.dev`                                                     | Model catalog, at startup and hourly          | `offline = true`, or mirror with `OPENCODE_MODELS_URL` |
| Runtime | `opencode.ai`                                                    | Update check                                  | On by default via `disable_autoupdate`                 |
| Runtime | `registry.npmjs.org`, GitHub                                     | Default plugins and language server downloads | `offline = true`                                       |
| Runtime | OpenCode share service                                           | Only when a user shares a session             | `"share": "disabled"` in `config_json`                 |
| Runtime | Provider APIs, or your Coder access URL with `enable_ai_gateway` | Model requests                                | Use AI Gateway                                         |

`offline = true` sets `OPENCODE_DISABLE_MODELS_FETCH`, `OPENCODE_DISABLE_AUTOUPDATE`, `OPENCODE_DISABLE_DEFAULT_PLUGINS` and `OPENCODE_DISABLE_LSP_DOWNLOAD` for the workspace. OpenCode then uses the model list built into the binary.

### Install from an internal mirror

`binary_url` downloads a binary, or a release archive with `opencode` at its top level (`.tar.gz` or `.zip`), and skips the installer. `{target}` becomes the OpenCode release target for the workspace (`x64`, `x64-baseline`, `x64-musl`, `x64-baseline-musl`, `arm64` or `arm64-musl`), so it matches the names of OpenCode's release archives. The module picks `-musl` on musl libc and `-baseline` on x64 CPUs without AVX2. `{arch}` becomes just `x64` or `arm64`. Mirror the archives your workspaces need.

```tf
module "opencode_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/opencode-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  opencode_version = "1.19.5"
  binary_url       = "https://artifacts.example.com/opencode/v1.19.5/opencode-linux-{target}.tar.gz"
  offline          = true
}
```

Pin `opencode_version` alongside `binary_url`: the module only replaces an installed binary whose version differs from the pin.

### Bring your own binary

Bake OpenCode 1.x into the image and skip installation entirely. The install script fails with a clear error if `opencode` is missing from `PATH` (or from `opencode_bin`, below) or is not 1.x.

```tf
module "opencode_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/opencode-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  install_opencode = false
  offline          = true
}
```

### Use OpenCode installed by mise

When a repository pins OpenCode in its `mise.toml` (`opencode = "1.19.5"`) and the template runs [`droopy4096/mise-install`](https://registry.coder.com/modules/droopy4096/mise-install), let mise provide the binary. `opencode_bin` points the module at it and skips installation, and `wait_for_scripts` holds the module back until `mise install` has finished:

```tf
module "mise_install" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/mise-install/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  repo_dir = module.git_clone[count.index].repo_dir
}

module "opencode_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/opencode-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  workdir          = module.git_clone[count.index].repo_dir
  opencode_bin     = "$HOME/.local/share/mise/installs/opencode/1.19.5/opencode"
  wait_for_scripts = module.mise_install[count.index].scripts
}
```

- Use mise's install path rather than its shim (`~/.local/share/mise/shims/opencode`). The shim only works in directories where a mise config selects OpenCode, and the module's scripts don't run in the repository.
- `wait_for_scripts` takes any `coder exp sync` names, such as another module's `scripts` output. The module waits up to 10 minutes, using the agent's own dependency tracking, and fails if they don't finish.
- `opencode_bin` also works for binaries baked into the image outside `PATH`.

Neither the install nor the start script uses `sudo`. Everything lives in the workspace user's home directory.

## Examples

### Pin a version and manage the config

`config_json` overwrites the global `opencode.json` on every start.

```tf
module "opencode_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/opencode-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  opencode_version = "1.19.5"
  config_json = jsonencode({
    "$schema" = "https://opencode.ai/config.json"
    share     = "disabled"
  })
}
```

### Serve several projects

Run one server per project on different ports. Instances on non-default ports get their own scripts, logs and app slug (`opencode-server-<port>`). Leave the workspace-wide environment settings to one instance:

```tf
module "opencode_api" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/droopy4096/opencode-server/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.main.id
  workdir            = "/home/coder/src/api"
  port               = 4097
  app_display_name   = "OpenCode (api)"
  disable_autoupdate = false # already set by the main instance
}
```

## Security

- The server listens on loopback only by default. Reach it through `coder port-forward` or the bundled app instead of exposing `hostname = "0.0.0.0"`.
- Anyone with the password can run commands in the workspace through the server API. The password file is `0600` and lives in your home directory.

## Troubleshooting

Logs live in `~/.coder-modules/droopy4096/opencode-server/logs/` (`install.log`, `start.log`, `server.log`). Instances on other ports use `opencode-server-<port>`.
