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
    -H "cookie: coder_session_token=$CODER_OWNER_SESSION_TOKEN" \
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

echo "Fetching public keys from GitHub..."
GITHUB_KEYS_RESPONSE=$(
  curl -L -s \
    -w "\n%%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    $GITHUB_API_URL/user/keys
)
GITHUB_KEYS_RESPONSE_STATUS=$(tail -n1 <<< "$GITHUB_KEYS_RESPONSE")
GITHUB_KEYS_RESPONSE_BODY=$(sed \$d <<< "$GITHUB_KEYS_RESPONSE")

if [ "$GITHUB_KEYS_RESPONSE_STATUS" -ne 200 ]; then
  echo "Failed to fetch Coder public SSH key with status code $GITHUB_KEYS_RESPONSE_STATUS!"
  echo "$GITHUB_KEYS_RESPONSE_BODY"
  exit 1
fi

GITHUB_MATCH=$(jq -r --arg PUBLIC_KEY "$PUBLIC_KEY" '.[] | select(.key == $PUBLIC_KEY) | .key' <<< "$GITHUB_KEYS_RESPONSE_BODY")

if [ "$PUBLIC_KEY" = "$GITHUB_MATCH" ]; then
  echo "Your Coder public key is already on GitHub!"
  exit 0
fi

echo "Your Coder public key is not in GitHub. Adding it now..."
CODER_PUBLIC_KEY_NAME="$CODER_ACCESS_URL Workspaces"
UPLOAD_RESPONSE=$(
  curl -L -s \
    -X POST \
    -w "\n%%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    $GITHUB_API_URL/user/keys \
    -d "{\"title\":\"$CODER_PUBLIC_KEY_NAME\",\"key\":\"$PUBLIC_KEY\"}"
)
UPLOAD_RESPONSE_STATUS=$(tail -n1 <<< "$UPLOAD_RESPONSE")
UPLOAD_RESPONSE_BODY=$(sed \$d <<< "$UPLOAD_RESPONSE")

if [ "$UPLOAD_RESPONSE_STATUS" -ne 201 ]; then
  echo "Failed to upload Coder public SSH key with status code $UPLOAD_RESPONSE_STATUS!"
  echo "$UPLOAD_RESPONSE_BODY"
  exit 1
fi

echo "Your Coder public key has been added to GitHub!"
