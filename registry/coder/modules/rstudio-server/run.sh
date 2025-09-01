#!/usr/bin/env sh

set -eu

BOLD='\033[0;1m'
RESET='\033[0m'

printf "$${BOLD}Starting RStudio Server (Rocker)...$${RESET}\n"

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
  delay=$(expr "$delay" \* 2) # exponential backoff
done

# Pull the specified version
IMAGE="rocker/rstudio:${SERVER_VERSION}"
docker pull "$${IMAGE}"

# Create (or reuse) a persistent renv cache volume
docker volume create "${RENV_CACHE_VOLUME}"

# Run container (auto-remove on stop)
docker run -d --rm \
  --name rstudio-server \
  -p "${PORT}:8787" \
  -e DISABLE_AUTH="${DISABLE_AUTH}" \
  -e USER="${RSTUDIO_USER}" \
  -e PASSWORD="${RSTUDIO_PASSWORD}" \
  -e RENV_PATHS_CACHE="/renv/cache" \
  -v "${PROJECT_PATH}:/home/${RSTUDIO_USER}/project" \
  -v "${RENV_CACHE_VOLUME}:/renv/cache" \
  "$${IMAGE}"

# Make RENV_CACHE_VOLUME writable to USER
docker exec rstudio-server bash -c 'chmod -R 0777 /renv/cache'

# Optional renv restore
if [ "${ENABLE_RENV}" = "true" ] && [ -f "${PROJECT_PATH}/renv.lock" ]; then
  echo "Restoring R environment via renv..."
  docker exec -u "${RSTUDIO_USER}" rstudio-server R -q -e \
    'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos="https://cloud.r-project.org"); renv::restore(prompt = FALSE)'
fi

[ "${DISABLE_AUTH}" != "true" ] && echo "User: ${RSTUDIO_USER}"

printf "\n$${BOLD}RStudio Server ${SERVER_VERSION} is running on port ${PORT}$${RESET}\n"
