#!/usr/bin/env bash
set -euo pipefail

# ---- configurable knobs (env overrides) ----
RUSTDESK_VERSION="${RUSTDESK_VERSION:-1.4.0}"
XVFB_RESOLUTION="${XVFB_RESOLUTION:-1024x768x16}"
RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD:-}"

# ---- detect package manager & arch ----
ARCH="$(uname -m)"
case "$ARCH" in
x86_64 | amd64) PKG_ARCH="x86_64" ;;
aarch64 | arm64) PKG_ARCH="aarch64" ;;
*)
	echo "Unsupported arch: $ARCH"
	exit 1
	;;
esac

if command -v apt-get >/dev/null 2>&1; then
	PKG_SYS="deb"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.deb"
	INSTALL_DEPS='apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y wget ca-certificates xvfb dbus-x11'
	INSTALL_CMD="apt-get install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
elif command -v dnf >/dev/null 2>&1; then
	PKG_SYS="rpm"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.rpm"
	INSTALL_DEPS='dnf install -y wget ca-certificates xorg-x11-server-Xvfb dbus-x11'
	INSTALL_CMD="dnf install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
elif command -v yum >/dev/null 2>&1; then
	PKG_SYS="rpm"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.rpm"
	INSTALL_DEPS='yum install -y wget ca-certificates xorg-x11-server-Xvfb dbus-x11'
	INSTALL_CMD="yum install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
else
	echo "Unsupported distro: need apt, dnf, or yum."
	exit 1
fi

# ---- install rustdesk if missing ----
if ! command -v rustdesk >/dev/null 2>&1; then
	echo "Installing dependencies…"
	bash -lc "$INSTALL_DEPS"

	echo "Downloading RustDesk ${RUSTDESK_VERSION} (${PKG_SYS}, ${PKG_ARCH})…"
	URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${PKG_NAME}"
	wget -q "$URL"

	echo "Installing RustDesk…"
	bash -lc "$INSTALL_CMD"

	echo "Cleaning up…"
	bash -lc "$CLEAN_CMD"
fi

# ---- start virtual display ----
echo "Starting Xvfb with resolution ${XVFB_RESOLUTION}…"
Xvfb :99 -screen 0 "${XVFB_RESOLUTION}" &
export DISPLAY=:99

# ---- create (or accept) password and start rustdesk ----
if [[ -z "${RUSTDESK_PASSWORD}" ]]; then
	RUSTDESK_PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 6)"
fi

# give the desktop a moment to come up if you launch XFCE/etc elsewhere
sleep 3

# set password (daemonless; rustdesk CLI handles it)
rustdesk --password "${RUSTDESK_PASSWORD}" >/dev/null 2>&1 || true
rustdesk &

sleep 3
RID="$(rustdesk --get-id || true)"

echo "-----------------------------"
echo " RustDesk ID:        ${RID}"
echo " RustDesk Password:  ${RUSTDESK_PASSWORD}"
echo " Display (Xvfb):     ${DISPLAY} (${XVFB_RESOLUTION})"
echo "-----------------------------"

# keep the script alive if needed (helpful in some runners)
wait -n || true
