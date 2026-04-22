#!/bin/bash

# Mock of the coder workspace CLI used in bun tests.
#
# The coder-utils module wraps scripts in `coder exp sync` calls for
# dependency ordering. Tests run inside a minimal container that does
# not ship a real coder binary, so this mock acknowledges the sync calls
# and exits 0.

if [[ "$1" == "exp" && "$2" == "sync" ]]; then
  exit 0
fi

# Fallback: unknown invocation, no-op.
exit 0
