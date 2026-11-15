# Incus has no guest agent for Windows, so `incus exec` and cloud-init do not
# work. The agent token goes to the guest on a small ISO instead, and a
# scheduled task in the golden image reads it at boot (windows/bootstrap.ps1).

variable "windows_image" {
  description = "Alias of the Windows golden image on the Incus host. The README explains how to build it."
  type        = string
  default     = "windows-server-2022"
}

module "windows_rdp" {
  count      = data.coder_workspace.me.start_count == 1 && local.is_windows ? 1 : 0
  source     = "registry.coder.com/coder/windows-rdp/coder"
  version    = "~> 1.4"
  agent_id   = coder_agent.main[0].id
  agent_name = "main"
}

# The instance depends on this resource, so Terraform destroys the instance
# first and the volume is free to delete.
resource "null_resource" "windows_seed_volume" {
  count = local.is_windows ? 1 : 0

  triggers = {
    pool   = var.storage_pool
    volume = local.seed_volume
  }

  provisioner "local-exec" {
    when    = destroy
    command = "incus storage volume delete \"${self.triggers.pool}\" \"${self.triggers.volume}\" 2>/dev/null || true"
  }
}

# The provider stops a VM without force and fails after 3 minutes. Windows
# can take longer when a user is logged on, so stop it here first.
resource "null_resource" "windows_stop" {
  count = local.is_windows ? 1 : 0

  triggers = {
    agent_token = local.agent_token
  }

  provisioner "local-exec" {
    command = "incus stop \"${local.instance_name}\" --timeout 120 2>/dev/null || incus stop \"${local.instance_name}\" --force 2>/dev/null || true"
  }
}

# The agent token changes on each start. Windows only sees a new CD-ROM at
# boot, so this runs while the VM is stopped and then starts it.
resource "null_resource" "windows_seed" {
  count = data.coder_workspace.me.start_count == 1 && local.is_windows ? 1 : 0

  triggers = {
    agent_token = local.agent_token
    instance    = incus_instance.dev.name
  }

  provisioner "local-exec" {
    environment = {
      INSTANCE          = incus_instance.dev.name
      POOL              = var.storage_pool
      VOLUME            = local.seed_volume
      CODER_AGENT_URL   = data.coder_workspace.me.access_url
      CODER_AGENT_TOKEN = local.agent_token
    }
    command = <<-EOT
      set -e
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      mkdir "$tmp/seed"
      printf 'CODER_AGENT_URL=%s\nCODER_AGENT_TOKEN=%s\n' "$CODER_AGENT_URL" "$CODER_AGENT_TOKEN" > "$tmp/seed/init.env"
      genisoimage -quiet -V CODER_INIT -J -R -o "$tmp/seed.iso" "$tmp/seed"
      incus config device remove "$INSTANCE" coder-init 2>/dev/null || true
      incus storage volume delete "$POOL" "$VOLUME" 2>/dev/null || true
      incus storage volume import "$POOL" "$tmp/seed.iso" "$VOLUME" --type=iso
      incus config device add "$INSTANCE" coder-init disk pool="$POOL" source="$VOLUME"
      incus start "$INSTANCE"
    EOT
  }
}
