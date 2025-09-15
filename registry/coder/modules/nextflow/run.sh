#!/usr/bin/env sh

set -eu

BOLD='\033[0;1m'
RESET='\033[0m'

printf "$${BOLD}Starting Nextflow...$${RESET}\n"

if ! command -v nextflow > /dev/null 2>&1; then
  # Update system dependencies
  sudo apt update
  sudo apt install openjdk-21-jdk graphviz salmon fastqc multiqc -y

  # Install nextflow
  export NXF_VER=${NEXTFLOW_VERSION}
  curl -s https://get.nextflow.io | bash
  sudo mv nextflow /usr/local/bin/
  sudo chmod +x /usr/local/bin/nextflow

  # Verify installation
  tmp_verify=$(mktemp -d coder-nextflow-XXXXXX)
  nextflow run hello \
    -with-report "$${tmp_verify}/report.html" \
    -with-trace "$${tmp_verify}/trace.txt" \
    -with-timeline "$${tmp_verify}/timeline.html" \
    -with-dag "$${tmp_verify}/flowchart.png"
  rm -r "$${tmp_verify}"
else
  echo "Nextflow is already installed\n\n"
fi

if [ ! -z ${PROJECT_PATH} ]; then
  # Project is located at PROJECT_PATH
  echo "Change directory: ${PROJECT_PATH}"
  cd ${PROJECT_PATH}
fi

# Start a web server to preview reports
mkdir -p ${HTTP_SERVER_REPORTS_DIR}
echo "Starting HTTP server in background, check logs: ${HTTP_SERVER_LOG_PATH}"
python3 -m http.server --directory ${HTTP_SERVER_REPORTS_DIR} ${HTTP_SERVER_PORT} > "${HTTP_SERVER_LOG_PATH}" 2>&1 &

# Stub run?
if [ "${STUB_RUN}" = "true" ]; then
  nextflow ${STUB_RUN_COMMAND} -stub-run
fi

printf "\n$${BOLD}Nextflow ${NEXTFLOW_VERSION} is ready. HTTP server is listening on port ${HTTP_SERVER_PORT}$${RESET}\n"
