# SPDX-FileCopyrightText: Copyright The Moby Authors
# SPDX-License-Identifier: Apache-2.0
# Based on Moby profiles/apparmor (vendored in moby/moby):
# https://github.com/moby/moby/blob/53f4b7843b21de61ed025bfaa669e967c697d112/vendor/github.com/moby/profiles/apparmor/template.go
# Changes: named opt-in profile; permit mount and pivot_root for nested sandboxes.
# Use only with a non-root container, all capabilities dropped and no-new-privileges.
abi <abi/3.0>,
#include <tunables/global>
profile coder-codex-sandbox flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  network,
  # Disallow obsolete socket families removed from the Linux kernel.
  # AF_DECnet has no AppArmor family name, so it cannot be denied here.
  deny network ax25,
  deny network ipx,
  deny network appletalk,
  deny network netrom,
  deny network rose,
  deny network econet,
  deny network atmsvc,
  deny network irda,
  deny network wanpipe,
  deny network isdn,
  deny network caif,
  # Disallow AF_ALG (Linux kernel crypto API); see https://copy.fail/
  deny network alg,
  # Disallow AF_VSOCK to prevent host/guest communication.
  deny network vsock,
  capability,
  file,
  umount,
  # Host (privileged) processes may send signals to container processes.
  signal (receive) peer=unconfined,
  # runc may send signals to container processes (for "docker stop").
  signal (receive) peer=runc,
  # crun may send signals to container processes (for "docker stop" when used with crun OCI runtime).
  signal (receive) peer=crun,
  # dockerd may send signals to container processes (for "docker kill").
  signal (receive) peer=unconfined,
  # Container processes may send signals amongst themselves.
  signal (send,receive) peer=coder-codex-sandbox,

  deny @{PROC}/* w,   # deny write for all files directly in /proc (not in a subdir)
  # deny write to files not in /proc/<number>/** or /proc/sys/**
  deny @{PROC}/{[^1-9/],[^1-9/][^0-9/],[^1-9s/][^0-9y/][^0-9s/],[^1-9/][^0-9/][^0-9/][^0-9/]*}/** w,
  deny @{PROC}/sys/[^k]** w,  # deny /proc/sys except /proc/sys/k* (effectively /proc/sys/kernel)
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]**} w,  # deny everything except shm* in /proc/sys/kernel/
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/kcore rwklx,

  mount,
  pivot_root,

  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/devices/virtual/powercap/** rwklx,
  deny /sys/kernel/security/** rwklx,

  # allow processes within the container to trace each other,
  # provided all other LSM and yama setting allow it.
  ptrace (trace,tracedby,read,readby) peer=coder-codex-sandbox,
}
