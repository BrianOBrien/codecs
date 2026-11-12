#!/bin/bash
# Run the Xojo build of xgt (its folder name has spaces, so the tests call this)
exec "$(dirname "$0")/Builds - xgt/Linux ARM64/xgt/xgt" "$@"
