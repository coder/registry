#!/usr/bin/env bash
# cloud-auth.sh — Multi-cloud auth helpers (source this file, don't execute)
# Supports:
#  - AWS:   access keys or IRSA (via pod SA)
#  - Azure: federated token or client secret
#  - GCP:   service account JSON or Workload Identity Federation (KSA -> SA)

set -euo pipefail

# -------- util --------
_has() { command -v "$1" > /dev/null 2>&1; }
_docker_ok() { _has docker && [[ -S /var/run/docker.sock ]]; }

cloud-auth-help() {
  cat << 'EOHELP'
Multi-Cloud Authentication Helper — source this file:

  source ~/workspace/cloud-auth.sh

Environment variables (read if set):

  # Common toggles (optional)
  ENABLE_AWS=true|false
  ENABLE_AZURE=true|false
  ENABLE_GCP=true|false

  # AWS
  AWS_REGION=us-west-2
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  AWS_SESSION_TOKEN=...        # optional (STS); if unset, IRSA/IMDS is used

  # Azure
  AZURE_CLIENT_ID=...
  AZURE_TENANT_ID=...
  AZURE_CLIENT_SECRET=...      # OR:
  AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token

  # GCP
  GCP_PROJECT_ID=...
  # Option A (Service Account JSON):
  GCP_SERVICE_ACCOUNT='{ ... }'
  # Option B (Workload Identity Federation):
  GCP_WORKLOAD_IDENTITY_PROVIDER=projects/..../locations/global/workloadIdentityPools/.../providers/...
  # (uses KSA token at /var/run/secrets/kubernetes.io/serviceaccount/token)

Functions:

  # AWS
  aws-login          # ensures creds (keys or IRSA), sets region config if provided
  aws-check          # prints caller identity
  aws-ecr-login      # docker login to ECR (if docker socket present)

  # Azure
  azure-login        # SP login via federated token OR client secret
  azure-check        # prints account info
  azure-acr-login    # docker login to ACR (requires AZURE_ACR_NAME)

  # GCP
  gcp-login          # SA JSON or WIF
  gcp-check          # prints active gcloud account & project
  gcp-gar-login      # docker auth to GAR (requires GCP_REGION & PROJECT)

  # Convenience
  multicloud-login   # calls the per-cloud logins if toggles are true
  multicloud-check   # calls the per-cloud checks
EOHELP
}

# -------- AWS --------
aws-login() {
  [[ "${ENABLE_AWS:-true}" == "true" ]] || {
    echo "AWS disabled"
    return 0
  }
  if ! _has aws; then
    echo "aws CLI not found"
    return 1
  fi

  # If access keys are present, write standard files; otherwise rely on IRSA/IMDS
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    mkdir -p "${HOME}/.aws"
    {
      echo "[default]"
      echo "aws_access_key_id=${AWS_ACCESS_KEY_ID}"
      echo "aws_secret_access_key=${AWS_SECRET_ACCESS_KEY:-}"
      [[ -n "${AWS_SESSION_TOKEN:-}" ]] && echo "aws_session_token=${AWS_SESSION_TOKEN}"
    } > "${HOME}/.aws/credentials"
    if [[ -n "${AWS_REGION:-}" ]]; then
      {
        echo "[default]"
        echo "region=${AWS_REGION}"
      } > "${HOME}/.aws/config"
    fi
  fi

  # Validate
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ AWS auth failed (neither valid keys nor IRSA available)"
    return 1
  fi
  echo "✅ AWS auth OK"
}

aws-check() {
  _has aws || {
    echo "aws CLI not found"
    return 1
  }
  aws sts get-caller-identity
}

aws-ecr-login() {
  _has aws || {
    echo "aws CLI not found"
    return 1
  }
  _docker_ok || {
    echo "ℹ️ docker socket not available; skipping ECR login"
    return 0
  }
  : "${AWS_REGION:=us-east-1}"
  aws-login > /dev/null || return 1
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin \
      "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  echo "✅ ECR login OK → ${ECR_REGISTRY}"
}

# -------- Azure --------
azure-login() {
  [[ "${ENABLE_AZURE:-false}" == "true" ]] || {
    echo "Azure disabled"
    return 0
  }
  _has az || {
    echo "az CLI not found"
    return 1
  }
  [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_TENANT_ID:-}" ]] || {
    echo "❌ Set AZURE_CLIENT_ID and AZURE_TENANT_ID"
    return 1
  }

  if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" && -f "${AZURE_FEDERATED_TOKEN_FILE}" ]]; then
    az login --service-principal \
      --username "${AZURE_CLIENT_ID}" \
      --tenant "${AZURE_TENANT_ID}" \
      --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" \
      --allow-no-subscriptions
  elif [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
    az login --service-principal \
      -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" \
      --tenant "${AZURE_TENANT_ID}"
  else
    echo "❌ Provide AZURE_FEDERATED_TOKEN_FILE or AZURE_CLIENT_SECRET"
    return 1
  fi

  echo "✅ Azure auth OK"
}

azure-check() {
  _has az || {
    echo "az CLI not found"
    return 1
  }
  az account show
}

azure-acr-login() {
  _has az || {
    echo "az CLI not found"
    return 1
  }
  _docker_ok || {
    echo "ℹ️ docker socket not available; skipping ACR login"
    return 0
  }
  [[ -n "${AZURE_ACR_NAME:-}" ]] || {
    echo "❌ Set AZURE_ACR_NAME"
    return 1
  }
  az account show > /dev/null 2>&1 || azure-login
  az acr login --name "${AZURE_ACR_NAME}"
  export ACR_REGISTRY="${AZURE_ACR_NAME}.azurecr.io"
  echo "✅ ACR login OK → ${ACR_REGISTRY}"
}

# -------- GCP --------
gcp-login() {
  [[ "${ENABLE_GCP:-false}" == "true" ]] || {
    echo "GCP disabled"
    return 0
  }
  _has gcloud || {
    echo "gcloud not found"
    return 1
  }

  if [[ -n "${GCP_SERVICE_ACCOUNT:-}" ]]; then
    # Service Account JSON path
    echo "${GCP_SERVICE_ACCOUNT}" > /tmp/gcp.json || {
      echo "❌ Failed to write GCP credentials"
      return 1
    }
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp.json || {
      echo "❌ Failed to set GCP credentials path"
      return 1
    }
    gcloud auth activate-service-account --key-file=/tmp/gcp.json --quiet || {
      echo "❌ GCP service account auth failed"
      return 1
    }
  else
    # Workload Identity Federation using KSA token + WIP provider
    [[ -n "${GCP_WORKLOAD_IDENTITY_PROVIDER:-}" && -n "${GCP_PROJECT_ID:-}" ]] || {
      echo "❌ Provide GCP_SERVICE_ACCOUNT JSON or set GCP_WORKLOAD_IDENTITY_PROVIDER & GCP_PROJECT_ID"
      return 1
    }
    [[ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]] || {
      echo "❌ KSA token not found"
      return 1
    }

    TMP="/tmp/gcp-wif-$$.json"
    cat > "${TMP}" << 'EOF'
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/${GCP_WORKLOAD_IDENTITY_PROVIDER}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "credential_source": {
    "file": "/var/run/secrets/kubernetes.io/serviceaccount/token",
    "format": { "type": "text" }
  }
}
EOF
    [[ $? -eq 0 ]] || {
      echo "❌ Failed to write GCP WIF config"
      return 1
    }
    export GOOGLE_APPLICATION_CREDENTIALS="${TMP}" || {
      echo "❌ Failed to set GCP credentials path"
      return 1
    }
    gcloud auth login --cred-file="${GOOGLE_APPLICATION_CREDENTIALS}" --quiet || {
      echo "❌ GCP WIF auth failed"
      return 1
    }
  fi

  if [[ -n "${GCP_PROJECT_ID:-}" ]]; then
    gcloud config set project "${GCP_PROJECT_ID}" --quiet
  fi
  echo "✅ GCP auth OK"
}

gcp-check() {
  _has gcloud || {
    echo "gcloud not found"
    return 1
  }
  gcloud auth list
  gcloud config get-value project || true
}

gcp-gar-login() {
  _docker_ok || {
    echo "ℹ️ docker socket not available; skipping GAR login"
    return 0
  }
  : "${GCP_REGION:=us-central1}"
  [[ -n "${GCP_PROJECT_ID:-}" ]] || {
    echo "❌ Set GCP_PROJECT_ID"
    return 1
  }
  gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null || gcp-login
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
  export GAR_REGISTRY="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}"
  echo "✅ GAR configured → ${GAR_REGISTRY}"
}

# -------- Convenience --------
multicloud-login() {
  if [[ "${ENABLE_AWS:-true}" == "true" ]]; then
    aws-login
  fi
  if [[ "${ENABLE_AZURE:-false}" == "true" ]]; then
    azure-login
  fi
  if [[ "${ENABLE_GCP:-false}" == "true" ]]; then
    gcp-login
  fi
  echo "✨ Multi-cloud login complete"
}

multicloud-check() {
  if [[ "${ENABLE_AWS:-true}" == "true" ]]; then
    echo "AWS:"
    aws-check
    echo
  fi
  if [[ "${ENABLE_AZURE:-false}" == "true" ]]; then
    echo "Azure:"
    azure-check
    echo
  fi
  if [[ "${ENABLE_GCP:-false}" == "true" ]]; then
    echo "GCP:"
    gcp-check
    echo
  fi
}

echo "✨ cloud-auth loaded. Run 'cloud-auth-help' for usage."
