# Reference snippets (from the Copilot v1 migration)

Concrete, working patterns extracted from `registry/coder-labs/modules/copilot`. Adapt names/paths to the target tool. These are illustrative, not drop-in.

## `coder_utils` wiring (main.tf)

```tf
locals {
  workdir                 = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  workdir_trusted_folders = local.workdir != "" ? [local.workdir] : []

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL               = tostring(var.install_copilot)
    ARG_COPILOT_VERSION       = var.copilot_version
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_MANAGED_SETTINGS_JSON = var.managed_settings != null ? base64encode(jsonencode(var.managed_settings)) : ""
    ARG_TRUSTED_FOLDERS       = length(local.workdir_trusted_folders) > 0 ? base64encode(jsonencode(local.workdir_trusted_folders)) : ""
    ARG_MCP_CONFIG            = var.mcp != "" ? base64encode(var.mcp) : ""
  })

  module_dir_name = ".coder-modules/coder-labs/copilot"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Copilot"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered coder exp sync names (pre_install, install, post_install)."
  value       = module.coder_utils.scripts
}
```

## Auth + model env (main.tf)

```tf
resource "coder_env" "copilot_model" {
  count    = var.copilot_model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "COPILOT_MODEL"
  value    = var.copilot_model
}

resource "coder_env" "github_token" {
  count    = var.github_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "COPILOT_GITHUB_TOKEN"
  value    = var.github_token
}
```

## managed_settings variable + root write

```tf
variable "managed_settings" {
  type        = any
  description = "Policy written to the tool's managed-settings file. Highest precedence; only supported keys apply. See <docs URL>."
  default     = null
}
```

```sh
# highest-precedence policy; rejected unless root-owned and not world-writable
write_managed_settings() {
  if [ -z "$${ARG_MANAGED_SETTINGS_JSON}" ]; then
    return
  fi
  if ! echo "$${ARG_MANAGED_SETTINGS_JSON}" | jq empty 2> /dev/null; then
    echo "Warning: managed_settings is not valid JSON, skipping policy write"
    return
  fi
  local target="/etc/github-copilot/managed-settings.json"
  if command_exists sudo; then
    sudo mkdir -p "$(dirname "$${target}")"
    echo "$${ARG_MANAGED_SETTINGS_JSON}" | sudo tee "$${target}" > /dev/null
    sudo chmod 0644 "$${target}"
  else
    mkdir -p "$(dirname "$${target}")"
    echo "$${ARG_MANAGED_SETTINGS_JSON}" > "$${target}"
    chmod 0644 "$${target}"
  fi
  echo "Wrote Copilot managed settings to $${target}"
}
```

## Official installer download/validate/run

```sh
install_with_official_installer() (
  local installer_file
  installer_file=$(mktemp)
  trap 'rm -f "$${installer_file}"' EXIT

  if ! curl --fail --silent --show-error --location \
    --retry 2 --retry-delay 1 --retry-all-errors \
    --connect-timeout 10 --max-time 300 \
    --output "$${installer_file}" https://gh.io/copilot-install; then
    echo "GitHub Copilot CLI could not be downloaded after up to 3 attempts." >&2
    return 1
  fi

  if ! bash -n "$${installer_file}"; then
    echo "GitHub Copilot CLI installer download was invalid." >&2
    return 1
  fi

  # VERSION accepts 'latest' or a version tag; PREFIX installs under $HOME/.local/bin.
  if ! VERSION="$${ARG_COPILOT_VERSION}" PREFIX="$HOME/.local" bash "$${installer_file}"; then
    echo "GitHub Copilot CLI installation failed." >&2
    return 1
  fi
)
```

## workdir trust (config.json trustedFolders, union, preserve rest)

```sh
setup_trusted_folders() {
  local config_file="$HOME/.copilot/config.json"
  [ -z "$${ARG_TRUSTED_FOLDERS}" ] && {
    echo "No workdir to trust."
    return
  }

  local existing='{}'
  if [ -f "$${config_file}" ] && jq empty "$${config_file}" > /dev/null 2>&1; then
    existing=$(cat "$${config_file}")
  fi
  echo "$${existing}" | jq --argjson folders "$${ARG_TRUSTED_FOLDERS}" \
    '.trustedFolders = (((.trustedFolders // []) + $folders) | unique)' > "$${config_file}"
}
```

## MCP merge (existing wins on duplicate names)

```sh
# right operand wins in jq '+', so existing on-disk servers win on duplicates
echo "$${existing}" | jq --argjson custom "$${custom}" \
  '.mcpServers = ($custom + (.mcpServers // {}))' > "$${mcp_config_file}"
```

## README launcher example

```tf
data "coder_external_auth" "github" {
  id = "github"
}

module "copilot" {
  source       = "registry.coder.com/coder-labs/copilot/coder"
  version      = "1.0.88"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder/project"
  github_token = data.coder_external_auth.github.access_token
}

resource "coder_app" "copilot" {
  agent_id     = coder_agent.example.id
  slug         = "copilot"
  display_name = "Copilot"
  icon         = "/icon/github.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "/home/coder/project"
    exec copilot --allow-all-tools
  EOT
}
```

## Copilot migration diff shape (for scale reference)

```
README.md            | rewritten
main.tf              | agentapi block + Tasks vars removed; coder_utils + config vars added
main.test.ts         | container tests rewritten
main.tftest.hcl      | new (replaces copilot.tftest.hcl)
copilot.tftest.hcl   | deleted
scripts/install.sh   | deleted (replaced by install.sh.tftpl)
scripts/start.sh     | deleted
scripts/install.sh.tftpl | new (official installer, config ownership)
testdata/*-mock.sh   | updated
```
