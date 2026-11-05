FROM debian:trixie-slim

ARG TARGETARCH=amd64
ARG OPENSHELL_VERSION=0.1.5
ARG DOCKER_VERSION=28.5.2

# The openshell CLI, the OpenShell gateway, and the Docker CLI. The gateway
# runs in the workspace Pod and creates the sandbox with its Docker driver.
RUN set -eu; \
	case "${TARGETARCH}" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1 ;; esac; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates curl; \
	rm -rf /var/lib/apt/lists/*; \
	base="https://github.com/NVIDIA/OpenShell/releases/download/v${OPENSHELL_VERSION}"; \
	curl -fsSL --retry 5 "${base}/openshell-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin openshell; \
	curl -fsSL --retry 5 "${base}/openshell-gateway-${arch}-unknown-linux-gnu.tar.gz" | tar -xz -C /usr/local/bin openshell-gateway; \
	curl -fsSL --retry 5 "https://download.docker.com/linux/static/stable/${arch}/docker-${DOCKER_VERSION}.tgz" | tar -xz -C /usr/local/bin --strip-components=1 docker/docker; \
	chmod 755 /usr/local/bin/openshell /usr/local/bin/openshell-gateway /usr/local/bin/docker; \
	openshell --version; \
	openshell-gateway --version; \
	docker --version

USER 1000:1000
