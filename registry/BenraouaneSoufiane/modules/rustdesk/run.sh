#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[0;1m'
RESET='\033[0m'

printf "${BOLD}🖥️  Installing RustDesk Remote Desktop\n${RESET}"

# ---- configurable knobs (env overrides) ----
RUSTDESK_VERSION="${RUSTDESK_VERSION:-latest}"
LOG_PATH="${LOG_PATH:-/tmp/rustdesk.log}"

# ---- fetch latest version if needed ----
if [ "$RUSTDESK_VERSION" = "latest" ]; then
	printf "🔍 Fetching latest RustDesk version...\n"
	RUSTDESK_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "1.4.1")
	printf "📌 Fetched RustDesk version: ${RUSTDESK_VERSION}\n"
else
	printf "📌 Using specified RustDesk version: ${RUSTDESK_VERSION}\n"
fi
XVFB_RESOLUTION="${XVFB_RESOLUTION:-1024x768x16}"
RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD:-}"

# ---- detect package manager & arch ----
ARCH="$(uname -m)"
case "$ARCH" in
x86_64 | amd64) PKG_ARCH="x86_64" ;;
aarch64 | arm64) PKG_ARCH="aarch64" ;;
*)
	echo "❌ Unsupported arch: $ARCH"
	exit 1
	;;
esac

if command -v apt-get >/dev/null 2>&1; then
	PKG_SYS="deb"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.deb"
	INSTALL_DEPS='apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y wget ca-certificates xvfb dbus-x11 xkb-data'
	INSTALL_CMD="apt-get install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
elif command -v dnf >/dev/null 2>&1; then
	PKG_SYS="rpm"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.rpm"
	INSTALL_DEPS='dnf install -y wget ca-certificates xorg-x11-server-Xvfb dbus-x11 xkeyboard-config'
	INSTALL_CMD="dnf install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
elif command -v yum >/dev/null 2>&1; then
	PKG_SYS="rpm"
	PKG_NAME="rustdesk-${RUSTDESK_VERSION}-${PKG_ARCH}.rpm"
	INSTALL_DEPS='yum install -y wget ca-certificates xorg-x11-server-Xvfb dbus-x11 xkeyboard-config'
	INSTALL_CMD="yum install -y ./${PKG_NAME}"
	CLEAN_CMD="rm -f \"${PKG_NAME}\""
else
	echo "❌ Unsupported distro: need apt, dnf, or yum."
	exit 1
fi

# ---- install rustdesk if missing ----
if ! command -v rustdesk >/dev/null 2>&1; then
	printf "📦 Installing dependencies...\n"
	sudo bash -c "$INSTALL_DEPS" 2>&1 | tee -a "${LOG_PATH}"

	printf "⬇️  Downloading RustDesk ${RUSTDESK_VERSION} (${PKG_SYS}, ${PKG_ARCH})...\n"
	URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${PKG_NAME}"
	wget -q "$URL" 2>&1 | tee -a "${LOG_PATH}"

	printf "🔧 Installing RustDesk...\n"
	sudo bash -c "$INSTALL_CMD" 2>&1 | tee -a "${LOG_PATH}"

	printf "🧹 Cleaning up...\n"
	bash -c "$CLEAN_CMD" 2>&1 | tee -a "${LOG_PATH}"
else
	printf "✅ RustDesk already installed\n"
fi

# ---- start virtual display ----
echo "Starting Xvfb with resolution ${XVFB_RESOLUTION}…"
Xvfb :99 -screen 0 "${XVFB_RESOLUTION}" &
export DISPLAY=:99

# ---- create (or accept) password and start rustdesk ----
if [[ -z "${RUSTDESK_PASSWORD}" ]]; then
	RUSTDESK_PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 6)"
fi

# give Xvfb a moment to start
sleep 2

printf "🔐 Setting RustDesk password and starting service...\n"
# set password (requires sudo for system service configuration)
sudo rustdesk --password "${RUSTDESK_PASSWORD}" >> "${LOG_PATH}" 2>&1 || true
rustdesk >> "${LOG_PATH}" 2>&1 &

sleep 3
RID="$(rustdesk --get-id 2>/dev/null || echo 'Unable to get ID')"

printf "🥳 RustDesk setup complete!\n\n"
printf "${BOLD}📋 Connection Details:${RESET}\n"
printf "   RustDesk ID:        ${RID}\n"
printf "   RustDesk Password:  ${RUSTDESK_PASSWORD}\n"
printf "   Display:            ${DISPLAY} (${XVFB_RESOLUTION})\n"
printf "\n📝 Logs available at: ${LOG_PATH}\n\n"

# keep the script alive if needed (helpful in some runners)
wait -n || true
