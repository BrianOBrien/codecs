#!/bin/bash
# Build xgt with the Xojo IDE (see tools/xojo-build.sh)
D="$(cd "$(dirname "$0")" && pwd)"
exec "$D/tools/xojo-build.sh" "$D/xgt.xojo_project" "$D/Builds - xgt/Linux ARM64/xgt/xgt"
