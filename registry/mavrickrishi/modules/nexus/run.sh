#!/usr/bin/env bash

not_configured() {
  type=$1
  echo "🤔 no $type repository is set, skipping $type configuration."
}

config_complete() {
  echo "🥳 Configuration complete!"
}

register_docker() {
  repo=$1
  echo -n "${NEXUS_PASSWORD}" | docker login "${NEXUS_HOST}" --username "${NEXUS_USERNAME}" --password-stdin
}

echo "🚀 Configuring Nexus repository access..."

# Configure Maven
if [ -n "${HAS_MAVEN}" ]; then
  echo "☕ Configuring Maven..."
  mkdir -p ~/.m2
  cat > ~/.m2/settings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <servers>
    <server>
      <id>nexus</id>
      <username>${NEXUS_USERNAME}</username>
      <password>${NEXUS_PASSWORD}</password>
    </server>
  </servers>
  <mirrors>
    <mirror>
      <id>nexus-mirror</id>
      <mirrorOf>*</mirrorOf>
      <url>${NEXUS_URL}/repository/${MAVEN_REPO}</url>
    </mirror>
  </mirrors>
</settings>
EOF
  config_complete
else
  not_configured maven
fi

# Configure npm
if [ -n "${HAS_NPM}" ]; then
  echo "📦 Configuring npm..."
  cat > ~/.npmrc << 'EOF'
${NPMRC}
EOF
  config_complete
else
  not_configured npm
fi

# Configure pip
if [ -n "${HAS_PYPI}" ]; then
  echo "🐍 Configuring pip..."
  mkdir -p ~/.pip
  # Create .netrc file for secure credential storage
  cat > ~/.netrc << EOF
machine ${NEXUS_HOST}
login ${NEXUS_USERNAME}
password ${NEXUS_PASSWORD}
EOF
  chmod 600 ~/.netrc

  # Update pip.conf to use index-url without embedded credentials
  cat > ~/.pip/pip.conf << 'EOF'
[global]
index-url = https://${NEXUS_HOST}/repository/${PYPI_REPO}/simple
EOF
  config_complete
else
  not_configured pypi
fi

# Configure Docker
if [ -n "${HAS_DOCKER}" ]; then
  if command -v docker > /dev/null 2>&1; then
    echo "🐳 Configuring Docker credentials..."
    mkdir -p ~/.docker
    ${REGISTER_DOCKER}
    config_complete
  else
    echo "🤔 Docker is not installed, skipping Docker configuration."
  fi
else
  not_configured docker
fi

echo "✅ Nexus repository configuration completed!"