#!/usr/bin/env bash
set -eu

# serve-web invokes this symlink in its commit cache. The link target sits
# beside the original server script in the selected platform's archive.
launcher=$(readlink "$0")
if [ "$VSCODE_WEB_DISABLE_TRUST" = true ]; then set -- --disable-workspace-trust "$@"; fi
if [ -n "$VSCODE_WEB_EXTENSIONS_DIR" ]; then set -- "--extensions-dir=$VSCODE_WEB_EXTENSIONS_DIR" "$@"; fi
exec "$(dirname "$launcher")/code-server" "$@"
