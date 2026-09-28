#!/usr/bin/env bash

# Regenerates instance-types.json from the AWS EC2 API. Edit the curated
# instance_types list below, then run this script and commit the result.
#
# Requires the AWS CLI with credentials allowed to call
# ec2:DescribeInstanceTypes. Override the query region with AWS_REGION
# (default us-east-1, which offers every type in the list).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_file="$script_dir/../instance-types.json"
region="${AWS_REGION:-us-east-1}"

# Curated types, grouped by the category main.tf derives from the family.
instance_types=(
  # general
  t3.nano t3.micro t3.small t3.medium t3.large t3.xlarge t3.2xlarge
  t4g.nano t4g.micro t4g.small t4g.medium t4g.large t4g.xlarge t4g.2xlarge
  m5.large m5.xlarge m5.2xlarge m5.4xlarge m5.8xlarge m5.12xlarge m5.16xlarge m5.24xlarge
  m7g.medium m7g.large m7g.xlarge m7g.2xlarge m7g.4xlarge m7g.8xlarge m7g.12xlarge m7g.16xlarge
  # compute
  c5.large c5.xlarge c5.2xlarge c5.4xlarge c5.9xlarge c5.12xlarge c5.18xlarge c5.24xlarge
  # memory
  r5.large r5.xlarge r5.2xlarge r5.4xlarge r5.8xlarge r5.12xlarge r5.16xlarge r5.24xlarge
  # storage
  i3.large i3.xlarge i3.2xlarge i3.4xlarge i3.8xlarge i3.16xlarge
  # gpu
  g4dn.xlarge g4dn.2xlarge g4dn.4xlarge g4dn.8xlarge g4dn.12xlarge g4dn.16xlarge
)

if ! command -v aws > /dev/null 2>&1; then
  echo "error: aws CLI not found; install and configure it first" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

aws ec2 describe-instance-types \
  --region "$region" \
  --instance-types "${instance_types[@]}" \
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
