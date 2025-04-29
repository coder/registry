#!/usr/bin/env bash
set -o pipefail
set -u

VERBOSE="${VERBOSE:-0}"
if [[ "${VERBOSE}" -ne "0" ]]; then
  set -x
fi

# List of required environment variables
required_vars=(
  "INSTATUS_API_KEY"
  "INSTATUS_PAGE_ID"
  "INSTATUS_COMPONENT_ID"
  "VERCEL_API_KEY"
)

# Check if each required variable is set
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Environment variable '$var' is not set."
    exit 1
  fi
done

REGISTRY_BASE_URL="${REGISTRY_BASE_URL:-https://registry.coder.com}"

status=0
declare -a modules=()
declare -a failures=()

# Collect all module directories containing a main.tf file
for path in $(find . -maxdepth 2 -not -path '*/.*' -type f -name main.tf | cut -d '/' -f 2 | sort -u); do
  modules+=("${path}")
done

echo "Checking modules: ${modules[*]}"

# Function to update the component status on Instatus
update_component_status() {
  local component_status=$1
  # see https://instatus.com/help/api/components
  (curl -X PUT "https://api.instatus.com/v1/$INSTATUS_PAGE_ID/components/$INSTATUS_COMPONENT_ID" \
    -H "Authorization: Bearer $INSTATUS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"status\": \"$component_status\"}")
}

# Function to create an incident
create_incident() {
  local incident_name="Degraded Service"
  local message="The following modules are experiencing issues:\n"
  for i in "${!failures[@]}"; do
    message+="$((i + 1)). ${failures[$i]}\n"
  done

  component_status="PARTIALOUTAGE"
  if ((${#failures[@]} == ${#modules[@]})); then
    component_status="MAJOROUTAGE"
  fi
  # see https://instatus.com/help/api/incidents
  incident_id=$(curl -s -X POST "https://api.instatus.com/v1/$INSTATUS_PAGE_ID/incidents" \
    -H "Authorization: Bearer $INSTATUS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
            \"name\": \"$incident_name\",
            \"message\": \"$message\",
            \"components\": [\"$INSTATUS_COMPONENT_ID\"],
            \"status\": \"INVESTIGATING\",
            \"notify\": true,
            \"statuses\": [
                {
                    \"id\": \"$INSTATUS_COMPONENT_ID\",
                    \"status\": \"PARTIALOUTAGE\"
                }
            ]
        }" | jq -r '.id')

  echo "Created incident with ID: $incident_id"
}

# Function to check for existing unresolved incidents
check_existing_incident() {
  # Fetch the latest incidents with status not equal to "RESOLVED"
  local unresolved_incidents=$(curl -s -X GET "https://api.instatus.com/v1/$INSTATUS_PAGE_ID/incidents" \
    -H "Authorization: Bearer $INSTATUS_API_KEY" \
    -H "Content-Type: application/json" | jq -r '.incidents[] | select(.status != "RESOLVED") | .id')

  if [[ -n "$unresolved_incidents" ]]; then
    echo "Unresolved incidents found: $unresolved_incidents"
    return 0 # Indicate that there are unresolved incidents
  else
    echo "No unresolved incidents found."
    return 1 # Indicate that no unresolved incidents exist
  fi
}

force_redeploy_registry() {
  # These are not secret values; safe to just expose directly in script
  local VERCEL_TEAM_SLUG="codercom"
  local VERCEL_TEAM_ID="team_tGkWfhEGGelkkqUUm9nXq17r"
  local VERCEL_APP="registry"

  local latest_res
  latest_res=$(
    curl "https://api.vercel.com/v6/deployments?app=$VERCEL_APP&limit=1&slug=$VERCEL_TEAM_SLUG&teamId=$VERCEL_TEAM_ID&target=production&state=BUILDING,INITIALIZING,QUEUED,READY" \
      --fail \
      --silent \
      --header "Authorization: Bearer $VERCEL_API_KEY" \
      --header "Content-Type: application/json"
  )

  # If we have zero deployments, something is VERY wrong. Make the whole
  # script exit with a non-zero status code
  local latest_id
  latest_id=$(echo "${latest_res}" | jq -r '.deployments[0].uid')
  if [[ "${latest_id}" = "null" ]]; then
    echo "Unable to pull any previous deployments for redeployment"
    echo "Please redeploy the latest deployment manually in Vercel."
    echo "https://vercel.com/codercom/registry/deployments"
    exit 1
  fi

  local latest_date_ts_seconds
  latest_date_ts_seconds=$(echo "${latest_res}" | jq -r '.deployments[0].createdAt/1000|floor')
  local current_date_ts_seconds
  current_date_ts_seconds="$(date +%s)"
  local max_redeploy_interval_seconds=7200 # 2 hours
  if ((current_date_ts_seconds - latest_date_ts_seconds < max_redeploy_interval_seconds)); then
    echo "The registry was deployed less than 2 hours ago."
    echo "Not automatically re-deploying the regitstry."
    echo "A human reading this message should decide if a redeployment is necessary."
    echo "Please check the Vercel dashboard for more information."
    echo "https://vercel.com/codercom/registry/deployments"
    exit 1
  fi

  local latest_deployment_state
  latest_deployment_state="$(echo "${latest_res}" | jq -r '.deployments[0].state')"
  if [[ "${latest_deployment_state}" != "READY" ]]; then
    echo "Last deployment was not in READY state. Skipping redeployment."
    echo "A human reading this message should decide if a redeployment is necessary."
    echo "Please check the Vercel dashboard for more information."
    echo "https://vercel.com/codercom/registry/deployments"
    exit 1
  fi

  echo "============================================================="
  echo "!!! Redeploying registry with deployment ID: ${latest_id} !!!"
  echo "============================================================="

  if ! curl -X POST "https://api.vercel.com/v13/deployments?forceNew=1&skipAutoDetectionConfirmation=1&slug=$VERCEL_TEAM_SLUG&teamId=$VERCEL_TEAM_ID" \
    --fail \
    --header "Authorization: Bearer $VERCEL_API_KEY" \
    --header "Content-Type: application/json" \
    --data-raw "{ \"deploymentId\": \"${latest_id}\", \"name\": \"${VERCEL_APP}\", \"target\": \"production\" }"; then
    echo "DEPLOYMENT FAILED! Please check the Vercel dashboard for more information."
    echo "https://vercel.com/codercom/registry/deployments"
    exit 1
  fi
}

# Check each module's accessibility
for module in "${modules[@]}"; do
  # Trim leading/trailing whitespace from module name
  module=$(echo "${module}" | xargs)
  url="${REGISTRY_BASE_URL}/modules/${module}"
  printf "=== Checking module %s at %s\n" "${module}" "${url}"
  status_code=$(curl --output /dev/null --head --silent --fail --location "${url}" --retry 3 --write-out "%{http_code}")
  if ((status_code != 200)); then
    printf "==> FAIL(%s)\n" "${status_code}"
    status=1
    failures+=("${module}")
  else
    printf "==> OK(%s)\n" "${status_code}"
  fi
done

# Determine overall status and update Instatus component
if ((status == 0)); then
  echo "All modules are operational."
  # set to
  update_component_status "OPERATIONAL"
else
  echo "The following modules have issues: ${failures[*]}"
  # check if all modules are down
  if ((${#failures[@]} == ${#modules[@]})); then
    update_component_status "MAJOROUTAGE"
  else
    update_component_status "PARTIALOUTAGE"
  fi

  # Check if there is an existing incident before creating a new one
  if ! check_existing_incident; then
    create_incident
  fi

  # If a module is down, force a reployment to try getting things back online
  # ASAP
  # EDIT: registry.coder.com is no longer hosted on vercel
  #force_redeploy_registry
fi

exit "${status}"
