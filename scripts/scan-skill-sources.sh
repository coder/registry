#!/usr/bin/env bash
# Usage: scripts/scan-skill-sources.sh [SARIF_OUT_DIR]
#
# Walks every registry/<namespace>/skills/README.md, extracts each unique
# owner/repo@ref from the YAML frontmatter under sources[].repo, and runs
# NVIDIA SkillSpector over the upstream GitHub repository. One SARIF file
# is written to SARIF_OUT_DIR (default ./sarif) per unique source.
#
# This script does NOT decide pass or fail on findings. It exits non-zero
# only when skillspector itself crashes. Severity gating lives in the
# workflow so the policy is visible alongside the deploy gate.

set -euo pipefail

OUT_DIR="${1:-./sarif}"
mkdir -p "${OUT_DIR}"

for bin in skillspector yq; do
  if ! command -v "${bin}" > /dev/null 2>&1; then
    echo "Required binary '${bin}' is not installed or not on PATH." >&2
    exit 2
  fi
done

declare -a readme_files=()
for f in registry/*/skills/README.md; do
  if [[ -f "${f}" ]]; then
    readme_files+=("${f}")
  fi
done

declare -a sources=()
if ((${#readme_files[@]} > 0)); then
  raw_sources=""
  for f in "${readme_files[@]}"; do
    frontmatter="$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "${f}")"
    extracted="$(printf '%s\n' "${frontmatter}" | yq -r '.sources[].repo')"
    raw_sources+="${extracted}"$'\n'
  done
  sorted_sources="$(printf '%s' "${raw_sources}" | sort -u | sed '/^$/d')"
  mapfile -t sources <<< "${sorted_sources}"
fi

if ((${#sources[@]} == 0)); then
  echo "No skills sources declared; nothing to scan."
  exit 0
fi

scan_failed=0
for src in "${sources[@]}"; do
  repo="${src%@*}"
  ref="${src#*@}"
  if [[ "${ref}" == "${src}" ]]; then
    ref="main"
  fi
  safe="${repo//\//_}__${ref}"
  echo "==> Scanning ${repo}@${ref}"
  if ! skillspector scan "https://github.com/${repo}" \
    --no-llm \
    --format sarif \
    --output "${OUT_DIR}/${safe}.sarif"; then
    echo "skillspector crashed scanning ${repo}@${ref}" >&2
    scan_failed=1
  fi
done

exit "${scan_failed}"
