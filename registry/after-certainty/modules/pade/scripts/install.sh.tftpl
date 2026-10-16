#!/usr/bin/env bash
set -euo pipefail

PADE_VERSION='${PADE_VERSION}'
BINDINGS_B64='${BINDINGS_B64}'
INSTALL_DIR="$HOME/.local/bin"
BINDINGS_PATH="$HOME/.config/pade/coder-bindings.yaml"

die() {
  echo "pade-coder: $*" >&2
  exit 1
}

for command in curl tar sha256sum base64 awk find; do
  command -v "$command" > /dev/null 2>&1 || die "required command not found: $command"
done

case "$(uname -s)" in
  Linux) os="linux" ;;
  *) die "Linux workspaces are required" ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) die "unsupported workspace architecture: $(uname -m)" ;;
esac

asset="pade-$PADE_VERSION-$os-$arch.tar.gz"
base_url="https://github.com/After-Certainty/pade/releases/download/$PADE_VERSION"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "pade-coder: installing PADE $PADE_VERSION ($os/$arch)"

curl --fail --silent --show-error --location --retry 2 \
  --connect-timeout 10 --max-time 300 \
  -o "$tmp/$asset" "$base_url/$asset"
curl --fail --silent --show-error --location --retry 2 \
  --connect-timeout 10 --max-time 60 \
  -o "$tmp/SHA256SUMS" "$base_url/SHA256SUMS"

awk -v asset="$asset" '$2 == asset { print }' "$tmp/SHA256SUMS" > "$tmp/SHA256SUMS.asset"
test -s "$tmp/SHA256SUMS.asset" || die "release checksum does not contain $asset"
(cd "$tmp" && sha256sum -c SHA256SUMS.asset)

mkdir -p "$tmp/extract" "$INSTALL_DIR" "$(dirname "$BINDINGS_PATH")"
tar -xzf "$tmp/$asset" -C "$tmp/extract"
pade_binary="$(find "$tmp/extract" -type f -name pade -print -quit)"
test -n "$pade_binary" || die "release archive did not contain the pade binary"

cp "$pade_binary" "$INSTALL_DIR/pade"
chmod 0755 "$INSTALL_DIR/pade"

bindings_tmp="$(mktemp "$BINDINGS_PATH.XXXXXX")"
printf '%s' "$BINDINGS_B64" | base64 -d > "$bindings_tmp"
chmod 0600 "$bindings_tmp"
mv "$bindings_tmp" "$BINDINGS_PATH"

add_shell_exports() {
  profile="$1"
  touch "$profile"
  grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$profile" \
    || printf '\n# pade-coder\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
  grep -qF 'export PADE_BINDINGS="$HOME/.config/pade/coder-bindings.yaml"' "$profile" \
    || printf 'export PADE_BINDINGS="$HOME/.config/pade/coder-bindings.yaml"\n' >> "$profile"
}

add_shell_exports "$HOME/.profile"
for profile in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do
  if [ -f "$profile" ]; then
    add_shell_exports "$profile"
  fi
done

if [ -f "$HOME/.config/fish/config.fish" ]; then
  grep -qF 'fish_add_path $HOME/.local/bin' "$HOME/.config/fish/config.fish" \
    || printf '\n# pade-coder\nfish_add_path $HOME/.local/bin\n' >> "$HOME/.config/fish/config.fish"
  grep -qF 'set -gx PADE_BINDINGS $HOME/.config/pade/coder-bindings.yaml' "$HOME/.config/fish/config.fish" \
    || printf 'set -gx PADE_BINDINGS $HOME/.config/pade/coder-bindings.yaml\n' >> "$HOME/.config/fish/config.fish"
fi

export PATH="$INSTALL_DIR:$PATH"
export PADE_BINDINGS="$BINDINGS_PATH"

"$INSTALL_DIR/pade" --version
echo "pade-coder: broker bindings written to $BINDINGS_PATH"
echo "pade-coder: Coder owns workspace lifecycle; workload identity comes from the workspace runtime"
