# Extend the administrator-selected Docker default allowlist; never start from
# an allow-all profile. This example supports x86_64 and aarch64 containers.
if .defaultAction != "SCMP_ACT_ERRNO" or (.syscalls | type) != "array" then
  error("Expected a Docker default seccomp allowlist with SCMP_ACT_ERRNO")
else
  .syscalls += [
    {
      "names": ["clone"],
      "action": "SCMP_ACT_ALLOW",
      "args": [{
        "index": 0,
        "value": 268435456,
        "valueTwo": 268435456,
        "op": "SCMP_CMP_MASKED_EQ"
      }],
      "includes": {"arches": ["amd64", "arm64"]}
    },
    {
      "names": ["unshare"],
      "action": "SCMP_ACT_ALLOW",
      "args": [{"index": 0, "value": 268435456, "op": "SCMP_CMP_EQ"}]
    },
    {"names": ["mount", "umount2", "pivot_root"], "action": "SCMP_ACT_ALLOW"}
  ]
end
