#!/usr/bin/env bash
# Builds and tests the local Swift packages (LifeOSKit).
#
# With full Xcode selected this is just `swift test`. With only the Command Line
# Tools (no Xcode), Swift Testing's framework and macro plugin aren't on the
# default search paths, so we add them explicitly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/LifeOSKit"
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"

EXTRA=()
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  FW="$DEV_DIR/Library/Developer/Frameworks"
  PLUGINS="$DEV_DIR/usr/lib/swift/host/plugins/testing"
  EXTRA=(--build-system native
         -Xswiftc -F -Xswiftc "$FW"
         -Xswiftc -plugin-path -Xswiftc "$PLUGINS"
         -Xlinker -F -Xlinker "$FW"
         -Xlinker -rpath -Xlinker "$FW")
fi

cd "$PKG"
swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
