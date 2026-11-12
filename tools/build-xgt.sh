#!/bin/bash
# Build xgt with the Xojo IDE (see tools/xojo-build.sh)
T="$(cd "$(dirname "$0")" && pwd)"
X="$(cd "$T/../xojo" && pwd)"
exec "$T/xojo-build.sh" "$X/xgt.xojo_project" "$X/Builds - xgt/Linux ARM64/xgt/xgt"
