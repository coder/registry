#!/usr/bin/env bash

if [ -z "$CODER_ACCESS_URL" ]; then
  if [ -z "${CODER_ACCESS_URL}" ]; then
    echo "CODER_ACCESS_URL is empty!"
    exit 1
  fi
  CODER_ACCESS_URL=${CODER_ACCESS_URL}
fi

if [ -z "$CODER_OWNER_SESSION_TOKEN" ]; then
  if [ -z "${CODER_OWNER_SESSION_TOKEN}" ]; then
    echo "CODER_OWNER_SESSION_TOKEN is empty!"
    exit 1
  fi
  CODER_OWNER_SESSION_TOKEN=${CODER_OWNER_SESSION_TOKEN}
fi

if [ -z "$CODER_EXTERNAL_AUTH_ID" ]; then
  if [ -z "${CODER_EXTERNAL_AUTH_ID}" ]; then
    echo "CODER_EXTERNAL_AUTH_ID is empty!"
    exit 1
  fi
  CODER_EXTERNAL_AUTH_ID=${CODER_EXTERNAL_AUTH_ID}
fi

if [ -z "$GITHUB_API_URL" ]; then
  if [ -z "${GITHUB_API_URL}" ]; then
    echo "GITHUB_API_URL is empty!"
    exit 1
  fi
  GITHUB_API_URL=${GITHUB_API_URL}
fi

echo "Fetching GitHub token..."
GITHUB_TOKEN=$(coder external-auth access-token $CODER_EXTERNAL_AUTH_ID)
if [ $? -ne 0 ]; then
  printf "Authenticate with Github to automatically upload Coder public key:\n$GITHUB_TOKEN\n"
  exit 1
fi

echo "Fetching public key from Coder..."
PUBLIC_KEY_RESPONSE=$(
  curl -L -s \
    -w "\n%%{http_code}" \
    -H 'accept: application/json' \
    -H "Coder-Session-Token: $CODER_OWNER_SESSION_TOKEN" \
    "$CODER_ACCESS_URL/api/v2/users/me/gitsshkey"
)
PUBLIC_KEY_RESPONSE_STATUS=$(tail -n1 <<< "$PUBLIC_KEY_RESPONSE")
PUBLIC_KEY_BODY=$(sed \$d <<< "$PUBLIC_KEY_RESPONSE")

if [ "$PUBLIC_KEY_RESPONSE_STATUS" -ne 200 ]; then
  echo "Failed to fetch Coder public SSH key with status code $PUBLIC_KEY_RESPONSE_STATUS!"
  echo "$PUBLIC_KEY_BODY"
  exit 1
fi
PUBLIC_KEY=$(jq -r '.public_key' <<< "$PUBLIC_KEY_BODY")
if [ -z "$PUBLIC_KEY" ]; then
  echo "No Coder public SSH key found!"
  exit 1
fi

CODER_PUBLIC_KEY_NAME="$(printf '%s' '${CODER_PUBLIC_KEY_NAME}' | base64 -d)"
[ -n "$CODER_PUBLIC_KEY_NAME" ] || CODER_PUBLIC_KEY_NAME="$CODER_ACCESS_URL Workspaces"

upload_key() {
  local endpoint="$1"
  local label="$2"

  echo "Fetching $label keys from GitHub..."
  local keys_response
  keys_response=$(
    curl -L -s \
      -w "\n%%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$GITHUB_API_URL/user/$endpoint"
  )
  local keys_status keys_body
  keys_status=$(tail -n1 <<< "$keys_response")
  keys_body=$(sed \$d <<< "$keys_response")

  if [ "$keys_status" -ne 200 ]; then
    echo "Failed to fetch GitHub $label keys with status code $keys_status!"
    echo "$keys_body"
    return 1
  fi

  local match
  match=$(jq -r --arg PUBLIC_KEY "$PUBLIC_KEY" '.[] | select(.key == $PUBLIC_KEY) | .key' <<< "$keys_body")
  if [ "$PUBLIC_KEY" = "$match" ]; then
    echo "Your Coder public key is already a GitHub $label key!"
    return 0
  fi

  echo "Your Coder public key is not a GitHub $label key yet. Adding it now..."
  local upload_response
  upload_response=$(
    curl -L -s \
      -X POST \
      -w "\n%%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$GITHUB_API_URL/user/$endpoint" \
      -d "$(jq -nc --arg title "$CODER_PUBLIC_KEY_NAME" --arg key "$PUBLIC_KEY" '{title: $title, key: $key}')"
  )
  local upload_status upload_body
  upload_status=$(tail -n1 <<< "$upload_response")
  upload_body=$(sed \$d <<< "$upload_response")

  if [ "$upload_status" -ne 201 ]; then
    echo "Failed to upload Coder public SSH key as a GitHub $label key with status code $upload_status!"
    echo "$upload_body"
    return 1
  fi

  echo "Your Coder public key has been added as a GitHub $label key!"
}

KEY_TYPE='${KEY_TYPE}'

if [ "$KEY_TYPE" = "auth" ] || [ "$KEY_TYPE" = "both" ]; then
  upload_key "keys" "authentication" || exit 1
fi

if [ "$KEY_TYPE" = "signing" ] || [ "$KEY_TYPE" = "both" ]; then
  upload_key "ssh_signing_keys" "signing" || exit 1
fi
