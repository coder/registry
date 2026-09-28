#!/usr/bin/env bash

# Regenerates instance-types.json from the AWS EC2 API. Edit the families list
# below, then run this script and commit the result. Sizes within each family
# are enumerated from AWS, so a newly released size is picked up automatically.
#
# Requires the AWS CLI with credentials allowed to call
# ec2:DescribeInstanceTypes. Override the query region with AWS_REGION
# (default us-east-1, which offers every family in the list).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_file="$script_dir/../instance-types.json"
region="${AWS_REGION:-us-east-1}"

# Instance families to offer. general: t3/t4g/m5/m7g, compute: c5, memory: r5,
# storage: i3, gpu: g4dn.
families=(t3 t4g m5 m7g c5 r5 i3 g4dn)

if ! command -v aws > /dev/null 2>&1; then
  echo "error: aws CLI not found; install and configure it first" >&2
  exit 1
fi

# Turn the families into an instance-type wildcard filter, e.g. "t3.*,m5.*".
family_filter=""
for family in "${families[@]}"; do
  family_filter="${family_filter:+$family_filter,}$family.*"
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# bare-metal=false keeps the catalog to virtualized sizes; .metal instances are
# not sensible workspace defaults. The AWS CLI paginates automatically.
aws ec2 describe-instance-types \
  --region "$region" \
  --filters "Name=instance-type,Values=${family_filter}" "Name=bare-metal,Values=false" \
  --output json \
  --query 'sort_by(InstanceTypes, &MemoryInfo.SizeInMiB)[].{value: InstanceType, vcpus: VCpuInfo.DefaultVCpus, memory_mib: MemoryInfo.SizeInMiB, gpus: (GpuInfo.Gpus[0].Count || `0`), ami: ProcessorInfo.SupportedArchitectures[-1]}' \
  > "$tmp"

mv "$tmp" "$output_file"

# AWS CLI emits 4-space JSON; match the repo's prettier formatting.
if command -v bun > /dev/null 2>&1; then
  bun x prettier --write "$output_file" > /dev/null
else
  echo "note: bun not found; run 'bun run fmt' before committing $output_file" >&2
fi

echo "Updated $output_file"
