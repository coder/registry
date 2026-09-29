#!/usr/bin/env bash
# Regenerate regions.json for the aws-region module from live AWS data.
# Requires the AWS CLI (any credentials) and jq.
set -euo pipefail

# Write regions.json in the module root; this script lives in .scripts/.
cd "$(dirname "$0")/.." || exit 1

# Two-letter country code -> Coder flag emoji asset (regional indicator pair).
icon() {
  local a b
  a=$(printf '%x' $((0x1f1e6 + $(printf '%d' "'${1:0:1}") - 0x61)))
  b=$(printf '%x' $((0x1f1e6 + $(printf '%d' "'${1:1:1}") - 0x61)))
  printf '/emojis/%s-%s.png' "$a" "$b"
}

for region in $(aws ec2 describe-regions --all-regions \
  --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort); do
  name=$(aws ssm get-parameter --region us-east-1 \
    --name "/aws/service/global-infrastructure/regions/$region/longName" \
    --query Parameter.Value --output text)
  # European regions share the EU flag; every other region uses its country flag.
  if [[ $region == eu-* ]]; then
    country=eu
  else
    country=$(aws ssm get-parameter --region us-east-1 \
      --name "/aws/service/global-infrastructure/regions/$region/geolocationCountry" \
      --query Parameter.Value --output text | tr '[:upper:]' '[:lower:]')
  fi
  jq -n --arg value "$region" --arg name "$name" --arg icon "$(icon "$country")" \
    '{$value, $name, $icon}'
done | jq -s '.' > regions.json
