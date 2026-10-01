#!/usr/bin/env bash
# Artifact integrity check for registry.coder.com.
#
# Kept separate from check_registry_site_health.sh. That script answers "is the
# registry reachable?" and reports availability to the public status page. This
# one answers "are responses coming from the registry application?", which
# warrants engineering triage rather than an automatic public status update, so
# this script has no Instatus credentials in scope.
#
# Every response from the registry application passes through
# serverVersionMiddleware and carries a Server-Version header, so a response
# without one did not come from the registry application.
#
# Scope: this verifies who answered the request, not what was served. It does
# not validate tarball contents against their source.
set -o pipefail
set -u

VERBOSE="${VERBOSE:-0}"
if [[ "${VERBOSE}" -ne "0" ]]; then
  set -x
fi

REGISTRY_BASE_URL="${REGISTRY_BASE_URL:-https://registry.coder.com}"
# Number of artifacts to probe per run. The header is a property of whoever
# answered rather than of the artifact requested, so a modest sample is enough;
# successive runs rotate through the full list so nothing is permanently
# excluded.
SAMPLE_COUNT="${SAMPLE_COUNT:-30}"

status=0
# Tracked separately: a missing header and a failed request have different
# causes, and conflating them makes a transient outage look like tampering.
declare -a integrity_failures=()
declare -a request_failures=()
declare -a modules=()

# Discover modules from the registry's own index so the probe list follows the
# registry rather than being hardcoded here. Entries are "<namespace>/<slug>".
modules_json="$(curl --silent --show-error --fail --max-time 60 \
  "${REGISTRY_BASE_URL}/api/modules")"
if [[ -z "${modules_json}" ]]; then
  echo "Error: unable to read the module index from ${REGISTRY_BASE_URL}/api/modules"
  exit 1
fi

mapfile -t modules < <(
  jq -r '.data[] | select(.contributorNamespace and .slug)
         | "\(.contributorNamespace)/\(.slug)"' <<< "${modules_json}" \
    | tr -d '\r' | sort
)

if ((${#modules[@]} == 0)); then
  echo "Error: no modules found in the registry index"
  exit 1
fi

total="${#modules[@]}"
window="${SAMPLE_COUNT}"
((window > total)) && window="${total}"

# Rotate the window so consecutive runs cover different modules.
offset=$((($(date +%s) / 900 * window) % total))

echo "Checking ${window} of ${total} module(s) against ${REGISTRY_BASE_URL}"

for ((i = 0; i < window; i++)); do
  entry="${modules[$(((offset + i) % total))]}"
  namespace="${entry%%/*}"
  module="${entry##*/}"

  # Ask the registry which versions it publishes and probe the newest, so the
  # check follows the registry rather than a stale list.
  versions_json="$(curl --silent --show-error --fail --max-time 45 \
    "${REGISTRY_BASE_URL}/terraform_protocol/${namespace}/${module}/coder/versions")"
  if [[ -z "${versions_json}" ]]; then
    printf '=== Checking %s/%s\n==> COULD NOT LIST VERSIONS\n' "${namespace}" "${module}"
    status=1
    request_failures+=("${namespace}/${module} (version listing failed)")
    continue
  fi

  version="$(jq -r '[.modules[0].versions[].version]
                    | sort_by(split(".") | map(tonumber? // 0))
                    | last // empty' <<< "${versions_json}" | tr -d '\r')"
  if [[ -z "${version}" ]]; then
    # The module index advertised this module, so the registry should be able
    # to list at least one version for it. Treat an empty list as a failure
    # rather than skipping, otherwise a run where nothing could be verified
    # still reports success.
    printf '=== Checking %s/%s\n==> NO VERSIONS PUBLISHED\n' "${namespace}" "${module}"
    status=1
    request_failures+=("${namespace}/${module} (no versions published)")
    continue
  fi

  # A unique query string keeps the CDN from answering, so that we observe the
  # origin rather than a cached response. The download handler also requires
  # that the client accept gzip.
  url="${REGISTRY_BASE_URL}/download/${namespace}/${version}-${module}.tar.gz?integrity=${RANDOM}${RANDOM}"

  printf '=== Checking %s/%s/%s\n' "${namespace}" "${module}" "${version}"

  headers="$(curl --head --silent --show-error --location --max-time 45 \
    --header 'Accept-Encoding: gzip' --retry 2 "${url}")"
  curl_status=$?

  if ((curl_status != 0)); then
    printf '==> FETCH FAILED (curl exit %s)\n' "${curl_status}"
    status=1
    request_failures+=("${namespace}/${module}/${version} (fetch failed)")
    continue
  fi

  if ! grep -qiE '^HTTP/[0-9.]+ 200' <<< "${headers}"; then
    printf '==> UNEXPECTED STATUS\n'
    status=1
    request_failures+=("${namespace}/${module}/${version} (unexpected status)")
    continue
  fi

  if ! grep -qi '^server-version:' <<< "${headers}"; then
    printf '==> MISSING Server-Version\n'
    status=1
    integrity_failures+=("${namespace}/${module}/${version}")
    continue
  fi

  printf '==> OK\n'
done

if ((status == 0)); then
  echo "All sampled responses came from the registry application."
  exit 0
fi

if ((${#request_failures[@]} > 0)); then
  echo
  echo "Requests that could not be completed:"
  for failure in "${request_failures[@]}"; do
    echo "  - ${failure}"
  done
  echo "These are usually availability problems. Check whether"
  echo "check-registry-site-health is also failing."
fi

if ((${#integrity_failures[@]} > 0)); then
  echo
  echo "Responses missing the Server-Version header:"
  for failure in "${integrity_failures[@]}"; do
    echo "  - ${failure}"
  done
  echo
  echo "These responses did not come from the registry application."
  echo "Escalate in #registry before taking remediation steps."
fi

exit "${status}"
