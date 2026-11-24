# Workspace image for the kubernetes-substrate template. It adds coder-boot
# as the entry point, and the CA of the Coder front in coder-bridge, to a
# base image that already has the Coder agent at /usr/local/bin/coder and a
# `coder` user with UID 1000, such as the image from
# ../../kubernetes-sandboxed/build/Dockerfile.
#
# Build from the template directory:
#   docker build -f build/Dockerfile --build-arg BASE=<base image> \
#     --build-arg BRIDGE_CA="$(cat ca.crt)" -t <workspace image> .
ARG BASE

FROM golang:1.25 AS build
WORKDIR /src
COPY bridge/go.mod ./
COPY bridge/cmd ./cmd
RUN CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /out/coder-boot ./cmd/coder-boot

FROM ${BASE}
ARG BRIDGE_CA
USER root
COPY --from=build /out/coder-boot /usr/local/bin/coder-boot
RUN set -eu
if [ -z "${BRIDGE_CA}" ]; then
  echo "Set BRIDGE_CA to the coder-bridge CA certificate" >&2
  exit 1
fi
printf '%s\n' "${BRIDGE_CA}" > /usr/local/share/ca-certificates/coder-bridge-ca.crt
update-ca-certificates > /dev/null
USER coder
ENTRYPOINT ["/usr/local/bin/coder-boot"]
