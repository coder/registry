#!/usr/bin/env bash

set -eo pipefail

error() {
  printf "💀 ERROR: %s\n" "$@"
  exit 1
}

# Function to check if KasmVNC is already installed
check_installed() {
  if command -v kasmvncserver &> /dev/null; then
    echo "KasmVNC is already installed."
    return 0 # Don't exit, just indicate it's installed
  else
    return 1 # Indicates not installed
  fi
}

# Function to download a file using wget, curl, or busybox as a fallback
download_file() {
  local url="$1"
  local output="$2"
  local download_tool

  if command -v curl &> /dev/null; then
    # shellcheck disable=SC2034
    download_tool=(curl -fsSL)
  elif command -v wget &> /dev/null; then
    # shellcheck disable=SC2034
    download_tool=(wget -q -O-)
  elif command -v busybox &> /dev/null; then
    # shellcheck disable=SC2034
    download_tool=(busybox wget -O-)
  else
    echo "ERROR: No download tool available (curl, wget, or busybox required)"
    exit 1
  fi

  # shellcheck disable=SC2288
  "$${download_tool[@]}" "$url" > "$output" || {
    echo "ERROR: Failed to download $url"
    exit 1
  }
}

# Function to install kasmvncserver for debian-based distros
install_deb() {
  local url=$1
  local kasmdeb="/tmp/kasmvncserver.deb"

  download_file "$url" "$kasmdeb"

  CACHE_DIR="/var/lib/apt/lists/partial"
  # Check if the directory exists and was modified in the last 60 minutes
  if [[ ! -d "$CACHE_DIR" ]] || ! find "$CACHE_DIR" -mmin -60 -print -quit &> /dev/null; then
    echo "Stale package cache, updating..."
    # Update package cache with a 300-second timeout for dpkg lock
    sudo apt-get -o DPkg::Lock::Timeout=300 -qq update
  fi

  echo "Installing required Perl DateTime module..."
  DEBIAN_FRONTEND=noninteractive sudo apt-get -o DPkg::Lock::Timeout=300 install --yes -qq --no-install-recommends --no-install-suggests libdatetime-perl

  DEBIAN_FRONTEND=noninteractive sudo apt-get -o DPkg::Lock::Timeout=300 install --yes -qq --no-install-recommends --no-install-suggests "$kasmdeb"
  rm "$kasmdeb"
}

# Function to install kasmvncserver for rpm-based distros
install_rpm() {
  local url=$1
  local kasmrpm="/tmp/kasmvncserver.rpm"
  local package_manager

  if command -v dnf &> /dev/null; then
    # shellcheck disable=SC2034
    package_manager=(dnf localinstall -y)
  elif command -v zypper &> /dev/null; then
    # shellcheck disable=SC2034
    package_manager=(zypper install -y)
  elif command -v yum &> /dev/null; then
    # shellcheck disable=SC2034
    package_manager=(yum localinstall -y)
  elif command -v rpm &> /dev/null; then
    # Do we need to manually handle missing dependencies?
    # shellcheck disable=SC2034
    package_manager=(rpm -i)
  else
    echo "ERROR: No supported package manager available (dnf, zypper, yum, or rpm required)"
    exit 1
  fi

  download_file "$url" "$kasmrpm"

  # shellcheck disable=SC2288
  sudo "$${package_manager[@]}" "$kasmrpm" || {
    echo "ERROR: Failed to install $kasmrpm"
    exit 1
  }

  rm "$kasmrpm"
}

# Function to install kasmvncserver for Alpine Linux
install_alpine() {
  local url=$1
  local kasmtgz="/tmp/kasmvncserver.tgz"

  download_file "$url" "$kasmtgz"

  tar -xzf "$kasmtgz" -C /usr/local/bin/
  rm "$kasmtgz"
}

# Detect system information
if [[ ! -f /etc/os-release ]]; then
  echo "ERROR: Cannot detect OS: /etc/os-release not found"
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

set -u

distro="$ID"
distro_version="$VERSION_ID"
codename="$VERSION_CODENAME"
arch="$(uname -m)"
if [[ "$ID" == "ol" ]]; then
  distro="oracle"
  distro_version="$${distro_version%%.*}"
elif [[ "$ID" == "fedora" ]]; then
  distro_version="$(grep -oP '\(\K[\w ]+' /etc/fedora-release | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
fi

echo "Detected Distribution: $distro"
echo "Detected Version: $distro_version"
echo "Detected Codename: $codename"
echo "Detected Architecture: $arch"

# Map arch to package arch
case "$arch" in
  x86_64)
    if [[ "$distro" =~ ^(ubuntu|debian|kali)$ ]]; then
      arch="amd64"
    fi
    ;;
  aarch64)
    if [[ "$distro" =~ ^(ubuntu|debian|kali)$ ]]; then
      arch="arm64"
    fi
    ;;
  arm64)
    : # This is effectively a noop
    ;;
  *)
    echo "ERROR: Unsupported architecture: $arch"
    exit 1
    ;;
esac

# Check if KasmVNC is installed, and install if not
if ! check_installed; then
  # Check for NOPASSWD sudo (required)
  if ! command -v sudo &> /dev/null || ! sudo -n true 2> /dev/null; then
    echo "ERROR: sudo NOPASSWD access required!"
    exit 1
  fi

  base_url="https://github.com/kasmtech/KasmVNC/releases/download/v${KASM_VERSION}"

  echo "Installing KASM version: ${KASM_VERSION}"
  case $distro in
    ubuntu | debian | kali)
      bin_name="kasmvncserver_$${codename}_${KASM_VERSION}_$${arch}.deb"
      install_deb "$base_url/$bin_name"
      ;;
    oracle | fedora | opensuse)
      bin_name="kasmvncserver_$${distro}_$${distro_version}_${KASM_VERSION}_$${arch}.rpm"
      install_rpm "$base_url/$bin_name"
      ;;
    alpine)
      bin_name="kasmvnc.alpine_$${distro_version//./}_$${arch}.tgz"
      install_alpine "$base_url/$bin_name"
      ;;
    *)
      echo "Unsupported distribution: $distro"
      exit 1
      ;;
  esac
else
  echo "KasmVNC already installed. Skipping installation."
fi

if command -v sudo &> /dev/null && sudo -n true 2> /dev/null; then
  kasm_config_file="/etc/kasmvnc/kasmvnc.yaml"
  SUDO=sudo
else
  kasm_config_file="$HOME/.vnc/kasmvnc.yaml"
  SUDO=""

  echo "WARNING: Sudo access not available, using user config dir!"

  if [[ -f "$kasm_config_file" ]]; then
    echo "WARNING: Custom user KasmVNC config exists, not overwriting!"
    echo "WARNING: Ensure that you manually configure the appropriate settings."
    kasm_config_file="/dev/stderr"
  else
    echo "WARNING: This may prevent custom user KasmVNC settings from applying!"
    mkdir -p "$HOME/.vnc"
  fi
fi

echo "Writing KasmVNC config to $kasm_config_file"
$SUDO tee "$kasm_config_file" > /dev/null << EOF
network:
  protocol: http
  interface: 127.0.0.1
  websocket_port: ${PORT}
  ssl:
    require_ssl: false
    pem_certificate:
    pem_key:
  udp:
    public_ip: 127.0.0.1
EOF

# This password is not used since we start the server without auth.
# The server is protected via the Coder session token / tunnel
# and does not listen publicly
echo -e "password\npassword\n" | kasmvncpasswd -wo -u "$USER"

get_http_dir() {
  # determine the served file path
  # Start with the default
  httpd_directory="/usr/share/kasmvnc/www"

  # Check the system configuration path
  if [[ -e /etc/kasmvnc/kasmvnc.yaml ]]; then
    d=$(grep -E '^\s*httpd_directory:.*$' "/etc/kasmvnc/kasmvnc.yaml" | awk '{print $$2}')
    if [[ -n "$d" && -d "$d" ]]; then
      httpd_directory=$d
    fi
  fi

  # Check the home directory for overriding values
  if [[ -e "$HOME/.vnc/kasmvnc.yaml" ]]; then
    d=$(grep -E '^\s*httpd_directory:.*$' "$HOME/.vnc/kasmvnc.yaml" | awk '{print $$2}')
    if [[ -n "$d" && -d "$d" ]]; then
      httpd_directory=$d
    fi
  fi
  echo $httpd_directory
}

fix_server_index_file() {
  local fname=$${FUNCNAME[0]} # gets current function name
  if [[ $# -ne 1 ]]; then
    error "$fname requires exactly 1 parameter:\n\tpath to KasmVNC httpd_directory"
  fi
  local httpdir="$1"
  if [[ ! -d "$httpdir" ]]; then
    error "$fname: $httpdir is not a directory"
  fi
  pushd "$httpdir" > /dev/null

  cat << 'EOH' > /tmp/path_vnc.html
${PATH_VNC_HTML}
EOH
  $SUDO mv /tmp/path_vnc.html .
  # check for the switcheroo
  if [[ -f "index.html" && -L "vnc.html" ]]; then
    $SUDO mv $httpdir/index.html $httpdir/vnc.html
  fi
  $SUDO ln -s -f path_vnc.html index.html
  popd > /dev/null
}

patch_kasm_http_files() {
  homedir=$(get_http_dir)
  fix_server_index_file "$homedir"
}

health_check_with_retries() {
  local max_attempts=3
  local attempt=1
  local supports_http_code=false

  if command -v curl &> /dev/null; then
    check_tool="curl -s -o /dev/null -w '%%{http_code}'"
    supports_http_code=true
  elif command -v wget &> /dev/null; then
    check_tool="wget -q -O- --server-response"
  elif command -v busybox &> /dev/null; then
    check_tool="busybox wget -O-"
  else
    echo "ERROR: No download tool available (curl, wget, or busybox required)"
    exit 1
  fi

  while (( attempt <= max_attempts )); do
    status=$($check_tool "http://127.0.0.1:${PORT}/app" 2>/dev/null)

    if $supports_http_code; then
      if [[ "$status" == "200" ]]; then
        return 0
      fi
    else
      if [[ -n "$status" ]]; then
        return 0
      fi
    fi

    echo "Attempt $attempt: service not ready yet"
    sleep 1
    ((attempt++))
  done
  return 1
}

debug() {
  [[ "$${DEBUG:-0}" == "1" ]] && echo "[DEBUG] $*" >&2
}

check_port_owned_by_user() {
  local port="$1"
  local user
  user="$(whoami)"

  debug "Checking port: $port"
  debug "Current user: $user"

  if command -v ss >/dev/null 2>&1; then
    debug "Using ss"

    local out
    out="$(ss -H -tlnp 2>&1)"
    debug "ss output:"
    debug "$out"

    echo "$out" | awk -v p=":$port" -v u="$user" '
      $4 ~ p && $7 ~ u { found=1 }
      END { exit !found }
    ' && return 0

    return 1
  fi

  if command -v netstat >/dev/null 2>&1; then
    debug "Using netstat"

    local out
    out="$(netstat -tlnp 2>&1)"
    debug "netstat output:"
    debug "$out"

    echo "$out" | awk -v p=":$port" -v u="$user" '
      $4 ~ p && $7 ~ u { found=1 }
      END { exit !found }
    ' && return 0

    return 1
  fi

  if command -v lsof >/dev/null 2>&1; then
    debug "Using lsof"

    local out
    out="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>&1)"
    debug "lsof output:"
    debug "$out"

    echo "$out" | awk -v u="$user" '
      $3 == u { found=1 }
      END { exit !found }
    ' && return 0

    return 1
  fi

  debug "No ss / netstat / lsof available"
  return 1
}


if [[ "${SUBDOMAIN}" == "false" ]]; then
  echo "🩹 Patching up webserver files to support path-sharing..."
  patch_kasm_http_files
fi

VNC_LOG="/tmp/kasmvncserver.log"
# Start the server
printf "🚀 Starting KasmVNC server...\n"

set +e
kasmvncserver -select-de "${DESKTOP_ENVIRONMENT}" -websocketPort "${PORT}" -disableBasicAuth > "$VNC_LOG" 2>&1
RETVAL=$?
set -e

if [[ $RETVAL -ne 0 ]]; then
  export DEBUG=1
  debug "KasmVNC error code: $RETVAL"
  if check_port_owned_by_user "${PORT}"; then
    echo "Port ${PORT} is already owned by $(whoami), running health check..."
    if ! health_check_with_retries; then
      echo "ERROR: KasmVNC server on port ${PORT} failed health check"
      [[ -f "$VNC_LOG" ]] && cat "$VNC_LOG"
      exit 1
    fi
  else
    echo "ERROR: Failed to start KasmVNC server. Return code: $RETVAL"
    [[ -f "$VNC_LOG" ]] && cat "$VNC_LOG"
    exit 1
  fi
fi

printf "🚀 KasmVNC server started successfully!\n"
