#!/usr/bin/env sh

set -eu

BOLD='\033[0;1m'
RESET='\033[0m'

printf "$${BOLD}Starting Perplexica...$${RESET}\n"

# Set Docker host if provided
if [ -n "${DOCKER_HOST}" ]; then
  export DOCKER_HOST="${DOCKER_HOST}"
fi

# Wait for docker to become ready
max_attempts=10
delay=2
attempt=1

while ! docker ps; do
  if [ $attempt -ge $max_attempts ]; then
    echo "Failed to list containers after $${max_attempts} attempts."
    exit 1
  fi
  echo "Attempt $${attempt} failed, retrying in $${delay}s..."
  sleep $delay
  attempt=$(expr "$attempt" + 1)
  delay=$(expr "$delay" \* 2)
done

# Pull the image
IMAGE="itzcrazykns1337/perplexica:latest"
docker pull "$${IMAGE}"

# Build docker run command
DOCKER_ARGS="-d --rm --name perplexica -p ${PORT}:3000"

# Add mounts - convert relative paths to absolute
DATA_PATH="${DATA_PATH}"
UPLOADS_PATH="${UPLOADS_PATH}"

mkdir -p "$${DATA_PATH}"
mkdir -p "$${UPLOADS_PATH}"

DATA_PATH_ABS=$(cd "$${DATA_PATH}" && pwd)
UPLOADS_PATH_ABS=$(cd "$${UPLOADS_PATH}" && pwd)

DOCKER_ARGS="$${DOCKER_ARGS} -v $${DATA_PATH_ABS}:/home/perplexica/data"
DOCKER_ARGS="$${DOCKER_ARGS} -v $${UPLOADS_PATH_ABS}:/home/perplexica/uploads"

# Add environment variables if provided
if [ -n "${OPENAI_API_KEY}" ]; then
  DOCKER_ARGS="$${DOCKER_ARGS} -e OPENAI_API_KEY=${OPENAI_API_KEY}"
fi

if [ -n "${ANTHROPIC_API_KEY}" ]; then
  DOCKER_ARGS="$${DOCKER_ARGS} -e ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
fi

if [ -n "${OLLAMA_API_URL}" ]; then
  DOCKER_ARGS="$${DOCKER_ARGS} -e OLLAMA_API_URL=${OLLAMA_API_URL}"
fi

# Run container
docker run $${DOCKER_ARGS} "$${IMAGE}"

printf "\n$${BOLD}Perplexica is running on port ${PORT}$${RESET}\n"
