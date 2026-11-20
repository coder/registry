# Codex sandbox in a Docker workspace

Installing `bubblewrap` does not grant permission to create namespaces. Docker's
default seccomp profile can reject `clone` with namespace flags; its default
AppArmor profile also denies mounts needed by bubblewrap. The Codex module runs
inside that boundary and cannot change the container or host policy.

This opt-in example permits nested sandboxes in a **non-root** Docker workspace
while retaining a seccomp allowlist, AppArmor enforcement, dropped capabilities,
and `no-new-privileges`. It expands the kernel operations available to workspace
processes. The host administrator must review that change for their threat model.
Do not apply these profiles to a root or privileged container, or combine them
with added capabilities, host namespaces, host devices, or a Docker socket mount.

## Diagnose the failing layer

Run as the same user as the Coder agent:

```bash
codex --version
bwrap --version
bwrap --unshare-user --ro-bind / / true
codex sandbox echo "hello World"
grep -E 'CapEff|NoNewPrivs|Seccomp' /proc/self/status
cat /proc/self/attr/current
```

`Seccomp: 2` indicates a filter is active; it does not identify a particular
denied syscall. An administrator can inspect the container's `SecurityOpt`, host
audit logs, and a trace such as:

```bash
strace -f -e trace=clone,unshare,mount,pivot_root \
  bwrap --unshare-user --ro-bind / / true
```

In the tested Docker configuration, `clone(...CLONE_NEWUSER...) = -1 EPERM`
was caused by seccomp. Allowing that operation exposed AppArmor's mount denial
(`Failed to make / slave: Permission denied`). The same messages can have other
causes: also check host user namespace limits and AppArmor/SELinux denials.
The Ubuntu `bwrap` package/profile alone does not override Docker's policies.

## Configure the container boundary

Install the distribution's `bubblewrap` package in the workspace image. Prepare
these files with the template, before creating the workspace:

1. Obtain and review the default seccomp JSON for your Docker Engine release from
   [Moby profiles](https://github.com/moby/profiles). Save it as
   `docker-default.json`. Keep that version pinned and maintained with the host;
   this example deliberately does not download a mutable profile at startup.
2. Generate the extended allowlist using [seccomp.jq](./seccomp.jq):

   ```bash
   jq -e -f seccomp.jq docker-default.json > codex-seccomp.json
   ```

   The filter retains the original rules and default denial. It adds `clone`
   only when `CLONE_NEWUSER` is set (x86_64/aarch64), `unshare(CLONE_NEWUSER)`,
   and the mount, unmount, and root-switch operations used inside the new user
   namespace. It does not grant `CAP_SYS_ADMIN` in the container's initial
   namespace. Existing explicit seccomp denials still take precedence over an
   allow rule; investigate them if the resulting profile still rejects setup.

3. On an AppArmor host, review [apparmor.profile](./apparmor.profile) and load it
   **on the Docker host**, under its separate name:

   ```bash
   sudo install -m 0644 apparmor.profile /etc/apparmor.d/coder-codex-sandbox
   sudo apparmor_parser -r /etc/apparmor.d/coder-codex-sandbox
   ```

   This is based on Moby's container profile, retaining its file, process, and
   network denials while permitting sandbox mounts and `pivot_root`. It does
   not replace `docker-default` or disable the host's user namespace restriction.
   A host using SELinux requires its own reviewed policy; this AppArmor example
   does not configure SELinux.

Add the following settings to the workspace's existing `docker_container`
resource. Use the image's actual non-root UID/GID; `1000:1000` is an example.
The Docker provider receives seccomp JSON content, while AppArmor is a profile
name already loaded on the Docker host:

```tf
resource "docker_container" "workspace" {
  # Existing image, agent entrypoint, environment, and volume configuration...
  user       = "1000:1000"
  privileged = false

  capabilities {
    drop = ["ALL"]
  }

  security_opts = [
    "no-new-privileges:true",
    "seccomp=${file("${path.module}/codex-seccomp.json")}",
    "apparmor=coder-codex-sandbox",
  ]
}
```

For a host without AppArmor, omit the AppArmor entry only. Apply through the
normal template workflow and recreate the container; restarting a process inside
an existing container cannot replace its seccomp filter. Keep Codex sandboxing
enabled. `--privileged`, `seccomp=unconfined`, `apparmor=unconfined`, and Codex's
`danger-full-access` mode are not part of this configuration.

## Verify execution and isolation

Test the real CLI after the Coder agent connects, then repeat after a workspace
stop/start. The namespace probe alone is not a complete sandbox test.

```bash
mkdir -p "$HOME/project" "$HOME/outside"
cd "$HOME/project"
codex sandbox echo "hello World"
codex sandbox -c 'sandbox_mode="workspace-write"' \
  sh -c 'echo allowed > sandbox-check.txt'
cat sandbox-check.txt
```

These commands must fail, and neither file may be created:

```bash
codex sandbox -c 'sandbox_mode="workspace-write"' \
  sh -c 'echo denied > "$HOME/outside/sandbox-denied.txt"'
codex sandbox -c 'sandbox_mode="read-only"' \
  sh -c 'echo denied > sandbox-readonly.txt'
```

Also verify that a network endpoint reachable outside the sandbox is denied
inside it when the selected policy disallows network access. Confirm
`CapEff: 0000000000000000`, `NoNewPrivs: 1`, `Seccomp: 2`, and (on AppArmor hosts)
`coder-codex-sandbox (enforce)` in the workspace process.

The configuration was tested with Codex 0.169.0, bubblewrap 0.11.1, Docker 29.5.2,
an Ubuntu 26.04 ARM64 workspace, and an Ubuntu 24.04 host with kernel 6.8 and
AppArmor enabled, using the [Moby seccomp allowlist at `9ee3204`](https://github.com/moby/profiles/blob/9ee3204f0d0cfa19ca2c6a7b0fcf5a2b353954ae/seccomp/default.json)
as the input to `seccomp.jq`. Validate other CLI/runtime versions and architectures in your
environment; the original reporter's exact image and host settings are unknown.
