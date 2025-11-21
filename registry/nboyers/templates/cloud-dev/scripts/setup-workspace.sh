#!/usr/bin/env bash
set -euo pipefail

# =========================
# Helpers & safe defaults
# =========================
log() { printf '%s %s\n' "👉" "$*"; }
ok() { printf '%s %s\n' "✅" "$*"; }
skip() { printf '%s %s\n' "⏭️" "$*"; }
warn() { printf '%s %s\n' "⚠️" "$*"; }

# Detect CPU arch (amd64/arm64)
arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) echo amd64 ;;
  esac
}

# Map to Docker static tarball arch names
docker_tar_arch() {
  case "$(arch)" in
    amd64) echo x86_64 ;;
    arm64) echo aarch64 ;;
    *) echo x86_64 ;;
  esac
}

SAFE_TMP="$(mktemp -d)"
trap 'rm -rf "$SAFE_TMP"' EXIT

safe_dl() { # url dest
  curl -fL --retry 5 --retry-delay 2 --connect-timeout 10 -o "$2" "$1" || {
    echo "Failed to download $1"
    return 1
  }
}

docker_ok() {
  command -v docker > /dev/null 2>&1 && [[ -S /var/run/docker.sock ]]
}

# Ensure user bin dir
mkdir -p "$HOME/.local/bin" "$HOME/workspace/app"
export PATH="$HOME/.local/bin:$PATH"

# Inputs (with sane defaults)
IAC_TOOL="${IAC_TOOL:-terraform}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.6.0}"

ENABLE_AWS="${ENABLE_AWS:-true}"
ENABLE_AZURE="${ENABLE_AZURE:-false}"
ENABLE_GCP="${ENABLE_GCP:-false}"

AWS_REGION="${AWS_REGION:-}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
AZURE_FEDERATED_TOKEN_FILE="${AZURE_FEDERATED_TOKEN_FILE:-}"

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_SERVICE_ACCOUNT="${GCP_SERVICE_ACCOUNT:-}" # full JSON if not using WIF

REPO_URL="${REPO_URL:-${repo_url:-}}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-${default_branch:-main}}"
WORKDIR="${WORKDIR:-$HOME/workspace/app}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${GIT_TOKEN:-}}"

GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          Multi-Cloud DevOps Workspace Setup (no sudo)          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo

# ==========================================================
# Write multi-cloud helper functions to ~/workspace/cloud-auth.sh
# ==========================================================
cat > "${HOME}/workspace/cloud-auth.sh" << 'EOAUTHSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

aws-ecr-login() {
  : "${AWS_REGION:=us-east-1}"
  if ! command -v aws >/dev/null 2>&1; then echo "aws CLI not found"; return 1; fi
  if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS creds not available (IRSA or keys)"; return 1; fi
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  if command -v docker >/dev/null 2>&1 && [[ -S /var/run/docker.sock ]]; then
    aws ecr get-login-password --region "${AWS_REGION}" | \
      docker login --username AWS --password-stdin \
      "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    echo "✅ ECR login OK → ${ECR_REGISTRY}"
  else
    echo "ℹ️ docker socket not available; skipping docker login"
  fi
}

aws-check() { aws sts get-caller-identity && echo "✓ AWS creds valid"; }

azure-login() {
  if ! command -v az >/dev/null 2>&1; then echo "az CLI not found"; return 1; fi
  if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" && -f "${AZURE_FEDERATED_TOKEN_FILE}" ]]; then
    az login --service-principal --username "${AZURE_CLIENT_ID}" \
      --tenant "${AZURE_TENANT_ID}" \
      --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" \
      --allow-no-subscriptions
  elif [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
    az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" --tenant "${AZURE_TENANT_ID}"
  else
    echo "❌ Provide AZURE_FEDERATED_TOKEN_FILE or AZURE_CLIENT_SECRET"; return 1
  fi
  echo "✅ Azure auth OK"; az account show
}

azure-acr-login() {
  [[ -n "${AZURE_ACR_NAME:-}" ]] || { echo "Set AZURE_ACR_NAME"; return 1; }
  az account show &>/dev/null || azure-login
  if command -v docker >/dev/null 2>&1 && [[ -S /var/run/docker.sock ]]; then
    az acr login --name "${AZURE_ACR_NAME}"
    export ACR_REGISTRY="${AZURE_ACR_NAME}.azurecr.io"
    echo "✅ ACR login OK → ${ACR_REGISTRY}"
  else
    echo "ℹ️ docker socket not available; skipping docker login"
  fi
}

azure-check() { az account show && echo "✓ Azure creds valid" || { echo "❌ Not logged in"; return 1; }; }

gcp-login() {
  if ! command -v gcloud >/dev/null 2>&1; then echo "gcloud not found"; return 1; fi
  if [[ -n "${GCP_SERVICE_ACCOUNT:-}" ]]; then
    # SA JSON auth
    echo "${GCP_SERVICE_ACCOUNT}" > /tmp/gcp.json || { echo "❌ Failed to write GCP credentials"; return 1; }
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp.json
    gcloud auth activate-service-account --key-file=/tmp/gcp.json --quiet || { echo "❌ GCP auth failed"; return 1; }
  else
    echo "❌ Provide GCP_SERVICE_ACCOUNT JSON (WIF path not configured here)"; return 1
  fi
  [[ -n "${GCP_PROJECT_ID:-}" ]] && gcloud config set project "${GCP_PROJECT_ID}" --quiet || true
  echo "✅ GCP auth OK"; gcloud auth list
}

gcp-gar-login() {
  : "${GCP_REGION:=us-central1}"
  [[ -n "${GCP_PROJECT_ID:-}" ]] || { echo "Set GCP_PROJECT_ID"; return 1; }
  gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null || gcp-login
  if command -v docker >/dev/null 2>&1 && [[ -S /var/run/docker.sock ]]; then
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    export GAR_REGISTRY="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}"
    echo "✅ GAR configured → ${GAR_REGISTRY}"
  else
    echo "ℹ️ docker socket not available; skipping docker login"
  fi
}

gcp-check() { gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null && echo "✓ GCP creds valid" || { echo "❌ Not logged in"; return 1; }; }

multicloud-login() {
  [[ "${ENABLE_AWS:-false}" == "true"   ]] && command -v aws    >/dev/null && aws-ecr-login || true
  [[ "${ENABLE_AZURE:-false}" == "true" ]] && command -v az     >/dev/null && azure-login  || true
  [[ "${ENABLE_GCP:-false}" == "true"   ]] && command -v gcloud >/dev/null && gcp-login    || true
  echo "✨ Multi-cloud login complete"
}

multicloud-check() {
  [[ "${ENABLE_AWS:-false}" == "true"   ]] && command -v aws    >/dev/null && { echo "AWS:"; aws-check; echo; } || true
  [[ "${ENABLE_AZURE:-false}" == "true" ]] && command -v az     >/dev/null && { echo "Azure:"; azure-check; echo; } || true
  [[ "${ENABLE_GCP:-false}" == "true"   ]] && command -v gcloud >/dev/null && { echo "GCP:"; gcp-check; echo; } || true
}

cloud-auth-help() {
  cat <<'EOHELP'
Multi-Cloud Authentication Helper

Functions:
  AWS:   aws-ecr-login, aws-check
  Azure: azure-login, azure-acr-login, azure-check
  GCP:   gcp-login, gcp-gar-login, gcp-check
  Multi: multicloud-login, multicloud-check, cloud-auth-help
EOHELP
  return 0
}

echo "✨ Multi-cloud auth helpers loaded. Run 'cloud-auth-help' for help."
EOAUTHSCRIPT
chmod +x "${HOME}/workspace/cloud-auth.sh"
ok "Created ${HOME}/workspace/cloud-auth.sh"
echo

# =========================
# IaC tooling
# =========================
log "Installing IaC tooling (${IAC_TOOL})"
case "$IAC_TOOL" in
  terraform)
    if ! command -v terraform > /dev/null 2>&1; then
      safe_dl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$(arch).zip" "$SAFE_TMP/tf.zip"
      unzip -q "$SAFE_TMP/tf.zip" -d "$HOME/.local/bin"
      ok "Terraform ${TERRAFORM_VERSION} installed"
    else
      ok "Terraform already installed ($(terraform version | head -1))"
    fi
    ;;
  cdk)
    if ! command -v npm > /dev/null 2>&1; then
      log "npm not found; installing Node via nvm"
      export NVM_DIR="$HOME/.nvm"
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      # shellcheck disable=SC1090
      . "$NVM_DIR/nvm.sh"
      nvm install --lts
      nvm use --lts
      # persist for future shells
      grep -q 'NVM_DIR' "$HOME/.bashrc" 2> /dev/null || {
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.bashrc"
        echo '. "$NVM_DIR/nvm.sh"' >> "$HOME/.bashrc"
      }
    fi
    npm install -g aws-cdk > /dev/null
    ok "AWS CDK installed ($(cdk --version))"
    ;;
  pulumi)
    if ! command -v pulumi > /dev/null 2>&1; then
      curl -fsSL https://get.pulumi.com | sh
      export PATH="$PATH:$HOME/.pulumi/bin"
      ok "Pulumi installed ($(pulumi version))"
    else
      ok "Pulumi already installed ($(pulumi version))"
    fi
    ;;
  *)
    warn "Unknown IAC_TOOL=${IAC_TOOL}; skipping IaC install"
    ;;
esac

# Extras: Terragrunt, tflint, tfsec, terraform-docs, pre-commit
if ! command -v terragrunt > /dev/null 2>&1; then
  TG_VER="0.54.0"
  safe_dl "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VER}/terragrunt_linux_$(arch)" "$HOME/.local/bin/terragrunt"
  chmod +x "$HOME/.local/bin/terragrunt"
  ok "Terragrunt v${TG_VER} installed"
fi

if ! command -v tflint > /dev/null 2>&1; then
  # official installer handles arch
  curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
  mv -f /tmp/tflint "$HOME/.local/bin/" 2> /dev/null || true
  ok "tflint installed"
fi

if ! command -v tfsec > /dev/null 2>&1; then
  TFSEC_VER="1.28.1"
  safe_dl "https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-$(arch)" "$HOME/.local/bin/tfsec"
  chmod +x "$HOME/.local/bin/tfsec"
  ok "tfsec v${TFSEC_VER} installed"
fi

if ! command -v terraform-docs > /dev/null 2>&1; then
  TFD_VER="0.17.0"
  safe_dl "https://github.com/terraform-docs/terraform-docs/releases/download/v${TFD_VER}/terraform-docs-v${TFD_VER}-linux-$(arch).tar.gz" "$SAFE_TMP/terraform-docs.tgz"
  tar -xzf "$SAFE_TMP/terraform-docs.tgz" -C "$SAFE_TMP"
  install -m 0755 "$SAFE_TMP/terraform-docs" "$HOME/.local/bin/terraform-docs"
  ok "terraform-docs v${TFD_VER} installed"
fi

if ! command -v pre-commit > /dev/null 2>&1; then
  if command -v pip3 > /dev/null 2>&1; then
    pip3 install --user --quiet pre-commit
    ok "pre-commit installed"
  elif command -v python3 > /dev/null 2>&1; then
    python3 -m pip install --user --quiet pre-commit
    ok "pre-commit installed"
  else
    warn "Python3/pip3 not found; skipping pre-commit"
  fi
fi

# =========================
# Cloud CLIs (user-space)
# =========================
echo
log "Installing Cloud CLIs (user-space)"

# AWS CLI v2
if [[ "${ENABLE_AWS}" == "true" ]] && ! command -v aws > /dev/null 2>&1; then
  safe_dl "https://awscli.amazonaws.com/awscli-exe-linux-$(arch).zip" "$SAFE_TMP/awscliv2.zip" \
    || safe_dl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "$SAFE_TMP/awscliv2.zip"
  unzip -q "$SAFE_TMP/awscliv2.zip" -d "$SAFE_TMP"
  "$SAFE_TMP/aws/install" -i "$HOME/.local/aws-cli" -b "$HOME/.local/bin" > /dev/null
  ok "AWS CLI installed"
fi

# Azure CLI
if [[ "${ENABLE_AZURE}" == "true" ]] && ! command -v az > /dev/null 2>&1; then
  if command -v pip3 > /dev/null 2>&1; then
    pip3 install --user --quiet azure-cli && ok "Azure CLI installed"
  elif command -v python3 > /dev/null 2>&1; then
    python3 -m pip install --user --quiet azure-cli && ok "Azure CLI installed"
  else
    warn "Python/pip not found; cannot install Azure CLI"
  fi
fi

# Google Cloud SDK
if [[ "${ENABLE_GCP}" == "true" ]] && ! command -v gcloud > /dev/null 2>&1; then
  GSDK_ARCH="$([[ "$(arch)" == amd64 ]] && echo x86_64 || echo arm)"
  safe_dl "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${GSDK_ARCH}.tar.gz" "$SAFE_TMP/gcloud.tgz"
  tar -xzf "$SAFE_TMP/gcloud.tgz" -C "$HOME"
  mv "$HOME/google-cloud-sdk" "$HOME/.local/google-cloud-sdk"
  ln -sf "$HOME/.local/google-cloud-sdk/bin/"{gcloud,gsutil,bq} "$HOME/.local/bin/" || true
  "$HOME/.local/google-cloud-sdk/install.sh" --quiet --rc-path /dev/null --path-update=false || true
  ok "Google Cloud SDK installed"
fi

# =========================
# Container & K8s tools
# =========================
echo
log "Installing container & Kubernetes tools"

# Docker CLI (client only)
if ! command -v docker > /dev/null 2>&1; then
  DOCKER_VER="25.0.5"
  safe_dl "https://download.docker.com/linux/static/stable/$(docker_tar_arch)/docker-${DOCKER_VER}.tgz" "$SAFE_TMP/docker.tgz"
  tar -xzf "$SAFE_TMP/docker.tgz" -C "$SAFE_TMP"
  install -m 0755 "$SAFE_TMP/docker/docker" "$HOME/.local/bin/docker"
  ok "Docker client installed"
fi

# kubectl
if ! command -v kubectl > /dev/null 2>&1; then
  KREL="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  safe_dl "https://dl.k8s.io/release/${KREL}/bin/linux/$(arch)/kubectl" "$SAFE_TMP/kubectl"
  install -m 0755 "$SAFE_TMP/kubectl" "$HOME/.local/bin/kubectl"
  ok "kubectl ${KREL} installed"
fi

# Helm
if ! command -v helm > /dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | USE_SUDO=false HELM_INSTALL_DIR="$HOME/.local/bin" bash
  ok "Helm installed"
fi

# jq / yq
if ! command -v jq > /dev/null 2>&1; then
  safe_dl "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$(arch)" "$HOME/.local/bin/jq"
  chmod +x "$HOME/.local/bin/jq"
  ok "jq installed"
fi

if ! command -v yq > /dev/null 2>&1; then
  safe_dl "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(arch)" "$HOME/.local/bin/yq"
  chmod +x "$HOME/.local/bin/yq"
  ok "yq installed"
fi

# =========================
# Cloud runtime auth (optional)
# =========================
echo
log "Configuring runtime cloud auth (if provided)"

# AWS keys (override IRSA if present)
if [[ "${ENABLE_AWS}" == "true" ]] && [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
  mkdir -p "$HOME/.aws"
  {
    echo "[default]"
    echo "aws_access_key_id=${AWS_ACCESS_KEY_ID}"
    echo "aws_secret_access_key=${AWS_SECRET_ACCESS_KEY:-}"
    [[ -n "$AWS_SESSION_TOKEN" ]] && echo "aws_session_token=${AWS_SESSION_TOKEN}"
  } > "$HOME/.aws/credentials" || { warn "Failed to write AWS credentials"; }
  if [[ -n "$AWS_REGION" ]]; then
    {
      echo "[default]"
      echo "region=${AWS_REGION}"
    } > "$HOME/.aws/config"
  fi
  ok "AWS runtime creds configured${AWS_REGION:+ (region ${AWS_REGION})}"
else
  skip "AWS runtime creds not set"
fi

# Azure SP (client secret path; federated handled by helper)
if [[ "${ENABLE_AZURE}" == "true" ]] && [[ -n "$AZURE_CLIENT_ID" && -n "$AZURE_TENANT_ID" ]]; then
  if command -v az > /dev/null 2>&1; then
    if [[ -n "$AZURE_FEDERATED_TOKEN_FILE" && -f "$AZURE_FEDERATED_TOKEN_FILE" ]]; then
      az login --service-principal --username "$AZURE_CLIENT_ID" \
        --tenant "$AZURE_TENANT_ID" \
        --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
        --allow-no-subscriptions > /dev/null
      ok "Azure federated login complete"
    elif [[ -n "$AZURE_CLIENT_SECRET" ]]; then
      az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" > /dev/null
      ok "Azure SP login complete"
    else
      skip "Azure creds not provided (need federated token file or client secret)"
    fi
  else
    warn "Azure CLI not found; skipping login"
  fi
else
  skip "Azure runtime auth not configured"
fi

# GCP SA JSON
if [[ "${ENABLE_GCP}" == "true" ]] && [[ -n "$GCP_SERVICE_ACCOUNT" ]]; then
  if command -v gcloud > /dev/null 2>&1; then
    echo "$GCP_SERVICE_ACCOUNT" > /tmp/gcp.json || { warn "Failed to write GCP credentials"; }
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp.json
    gcloud auth activate-service-account --key-file=/tmp/gcp.json > /dev/null || { warn "GCP auth failed"; }
    [[ -n "$GCP_PROJECT_ID" ]] && gcloud config set project "$GCP_PROJECT_ID" --quiet || true
    ok "GCP SA auth complete"
  else
    warn "gcloud not found; skipping GCP auth"
  fi
else
  skip "GCP runtime auth not configured"
fi

# =========================
# Git identity & bootstrap
# =========================
echo
log "Preparing workspace directory"

# Git identity
if [[ -n "$GIT_AUTHOR_NAME" ]]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [[ -n "$GIT_AUTHOR_EMAIL" ]]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

mkdir -p "$WORKDIR"

# Clone or init
if [[ -n "$REPO_URL" ]]; then
  URL="$REPO_URL"
  if [[ -n "$GITHUB_TOKEN" && "$URL" =~ ^https://github.com/ ]]; then
    URL="${URL/https:\/\//https:\/\/${GITHUB_TOKEN}@}" || { warn "Failed to modify URL"; }
    warn "Using GITHUB_TOKEN for private repo clone"
  fi
  if [[ ! -d "$WORKDIR/.git" ]]; then
    log "Cloning ${REPO_URL} into ${WORKDIR}"
    git clone "$URL" "$WORKDIR" || { warn "Failed to clone repository"; }
    pushd "$WORKDIR" > /dev/null
    git checkout "$DEFAULT_BRANCH" || git checkout -b "$DEFAULT_BRANCH"
    popd > /dev/null
    ok "Repository ready @ ${DEFAULT_BRANCH}"
  else
    ok "Repo already present at ${WORKDIR}"
  fi
else
  if [[ ! -d "$WORKDIR/.git" ]]; then
    log "Initializing empty repository in ${WORKDIR}"
    git init -q "$WORKDIR"
    pushd "$WORKDIR" > /dev/null
    git checkout -b "$DEFAULT_BRANCH" > /dev/null 2>&1 || true
    popd > /dev/null
  fi
  ok "Workspace ready at ${WORKDIR}"
fi

# =========================
# Company Terraform skeleton
# =========================
echo
log "Creating company Terraform skeleton (optional)"
mkdir -p "$WORKDIR/terraform"/{environments/{dev,staging,prod},modules,policies,shared}
cat > "$WORKDIR/terraform/README.md" << 'EOREADME'
# Company Terraform Project
- `environments/` contains per-env stacks.
- `modules/` reusable infra modules.
- `policies/` sentinel/policy-as-code.
- `shared/` backend, providers, etc.
EOREADME
ok "Skeleton present at $WORKDIR/terraform"

# =========================
# PATH persistence tip
# =========================
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2> /dev/null; then
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.bashrc"
fi

echo
ok "Workspace ready!"
echo "  • IaC tool:        ${IAC_TOOL}"
echo "  • AWS enabled:     ${ENABLE_AWS}"
echo "  • Azure enabled:   ${ENABLE_AZURE}"
echo "  • GCP enabled:     ${ENABLE_GCP}"
[[ -d "$WORKDIR/.git" ]] && echo "  • Repo:            ${REPO_URL:-<none>} @ ${DEFAULT_BRANCH}"
echo "  • Auth helpers:    source ~/workspace/cloud-auth.sh"
