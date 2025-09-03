#!/usr/bin/env bash

BOLD='\033[0;1m'

not_configured() {
  type=$1
  echo "🤔 no $type repository is set, skipping $type configuration."
  echo "You can configure a $type repository by providing a key for '$type' in the 'package_managers' input."
}

config_complete() {
  echo "🥳 Configuration complete!"
}

register_docker() {
  repo=$1
  echo -n "${ARTIFACTORY_ACCESS_TOKEN}" | docker login "$repo" --username ${ARTIFACTORY_USERNAME} --password-stdin
}

# check if JFrog CLI is already installed
if command -v jf > /dev/null 2>&1; then
  echo "✅ JFrog CLI is already installed, skipping installation."
else
  echo "📦 Installing JFrog CLI..."
  curl -fL https://install-cli.jfrog.io | sudo sh
  sudo chmod 755 /usr/local/bin/jf
fi

# The jf CLI checks $CI when determining whether to use interactive flows.
export CI=true
# Authenticate JFrog CLI with Artifactory.
echo "${ARTIFACTORY_ACCESS_TOKEN}" | jf c add --access-token-stdin --url "${JFROG_URL}" --overwrite "${JFROG_SERVER_ID}"
# Set the configured server as the default.
jf c use "${JFROG_SERVER_ID}"

# Configure npm to use the Artifactory "npm" repository.
if [ -z "${HAS_NPM}" ]; then
  not_configured npm
else
  echo "📦 Configuring npm..."
  jf npmc --global --repo-resolve "${REPOSITORY_NPM}"
  cat << EOF > ~/.npmrc
${NPMRC}
EOF
  config_complete
fi

# Configure the `pip` to use the Artifactory "python" repository.
if [ -z "${HAS_PYPI}" ]; then
  not_configured pypi
else
  echo "🐍 Configuring pip..."
  jf pipc --global --repo-resolve "${REPOSITORY_PYPI}"
  mkdir -p ~/.pip
  cat << EOF > ~/.pip/pip.conf
${PIP_CONF}
EOF
  config_complete
fi

# Configure Artifactory "go" repository.
if [ -z "${HAS_GO}" ]; then
  not_configured go
else
  echo "🐹 Configuring go..."
  jf goc --global --repo-resolve "${REPOSITORY_GO}"
  config_complete
fi

# Configure the JFrog CLI to use the Artifactory "docker" repository.
if [ -z "${HAS_DOCKER}" ]; then
  not_configured docker
else
  if command -v docker > /dev/null 2>&1; then
    echo "🔑 Configuring 🐳 docker credentials..."
    mkdir -p ~/.docker
    ${REGISTER_DOCKER}
  else
    echo "🤔 no docker is installed, skipping docker configuration."
  fi
fi

# Configure conda to use the Artifactory "conda" repository.
if [ -z "${HAS_CONDA}" ]; then
  not_configured conda
else
  echo "🐍 Configuring conda..."
  # Create conda config directory if it doesn't exist
  mkdir -p ~/.conda
  cat << EOF > ~/.condarc
${CONDA_CONF}
EOF
  config_complete
fi

# Install the JFrog vscode extension for code-server.
if [ "${CONFIGURE_CODE_SERVER}" == "true" ]; then
  while ! [ -x /tmp/code-server/bin/code-server ]; do
    counter=0
    if [ $counter -eq 60 ]; then
      echo "Timed out waiting for /tmp/code-server/bin/code-server to be installed."
      exit 1
    fi
    echo "Waiting for /tmp/code-server/bin/code-server to be installed..."
    sleep 1
    ((counter++))
  done
  echo "📦 Installing JFrog extension..."
  /tmp/code-server/bin/code-server --install-extension jfrog.jfrog-vscode-extension
  echo "🥳 JFrog extension installed!"
else
  echo "🤔 Skipping JFrog extension installation. Set configure_code_server to true to install the JFrog extension."
fi

# Configure the JFrog CLI completion
echo "📦 Configuring JFrog CLI completion..."
# Get the user's shell
SHELLNAME=$(grep "^$USER" /etc/passwd | awk -F':' '{print $7}' | awk -F'/' '{print $NF}')
# Generate the completion script
jf completion $SHELLNAME --install
begin_stanza="# BEGIN: jf CLI shell completion (added by coder module jfrog-token)"
# Add the completion script to the user's shell profile
if [ "$SHELLNAME" == "bash" ] && [ -f ~/.bashrc ]; then
  if ! grep -q "$begin_stanza" ~/.bashrc; then
    printf "%s\n" "$begin_stanza" >> ~/.bashrc
    echo 'source "$HOME/.jfrog/jfrog_bash_completion"' >> ~/.bashrc
    echo "# END: jf CLI shell completion" >> ~/.bashrc
  else
    echo "🥳 ~/.bashrc already contains jf CLI shell completion configuration, skipping."
  fi
elif [ "$SHELLNAME" == "zsh" ] && [ -f ~/.zshrc ]; then
  if ! grep -q "$begin_stanza" ~/.zshrc; then
    printf "\n%s\n" "$begin_stanza" >> ~/.zshrc
    echo "autoload -Uz compinit" >> ~/.zshrc
    echo "compinit" >> ~/.zshrc
    echo 'source "$HOME/.jfrog/jfrog_zsh_completion"' >> ~/.zshrc
    echo "# END: jf CLI shell completion" >> ~/.zshrc
  else
    echo "🥳 ~/.zshrc already contains jf CLI shell completion configuration, skipping."
  fi
else
  echo "🤔 ~/.bashrc or ~/.zshrc does not exist, skipping jf CLI shell completion configuration."
fi
