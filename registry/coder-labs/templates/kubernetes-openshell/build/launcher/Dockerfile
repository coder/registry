FROM alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0

ARG TARGETARCH=amd64
ARG OPENSHELL_VERSION=0.1.5

# The openshell CLI. Use the version of your gateway.
RUN set -eu; \
	case "${TARGETARCH}" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1 ;; esac; \
	wget -qO- "https://github.com/NVIDIA/OpenShell/releases/download/v${OPENSHELL_VERSION}/openshell-${arch}-unknown-linux-musl.tar.gz" \
		| tar -xz -C /usr/local/bin openshell; \
	chmod 755 /usr/local/bin/openshell; \
	/usr/local/bin/openshell --version

USER 1000:1000
