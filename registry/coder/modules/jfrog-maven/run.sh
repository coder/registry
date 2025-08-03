#!/usr/bin/env bash

BOLD='\033[0;1m'

not_configured() {
  echo "🤔 no Maven repositories are set, skipping Maven configuration."
  echo "You can configure Maven repositories by providing a list for 'maven_repositories' input."
}

config_complete() {
  echo "🥳 Maven configuration complete!"
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

# Configure Maven to use the Artifactory repositories.
if [ -z "${HAS_MAVEN}" ]; then
  not_configured
else
  if command -v mvn > /dev/null 2>&1; then
    echo "☕ Configuring Maven..."
    jf mvc --global --repo-resolve "${REPOSITORY_MAVEN}"
    mkdir -p ~/.m2
    cat << EOF > ~/.m2/settings.xml
${MAVEN_SETTINGS}
EOF
    config_complete
  else
    echo "🤔 no maven is installed, skipping maven configuration."
  fi
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
begin_stanza="# BEGIN: jf CLI shell completion (added by coder module jfrog-maven)"
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