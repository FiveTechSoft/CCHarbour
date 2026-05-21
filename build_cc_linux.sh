#!/bin/sh
# Linux build script for CCHarbour.
# Requires Harbour (hbmk2 in PATH) and a C compiler (gcc/clang).
# Produces ./cc
set -e
cd "$(dirname "$0")"

if ! command -v hbmk2 >/dev/null 2>&1; then
   echo "Error: hbmk2 not found in PATH. Install Harbour first." >&2
   exit 1
fi

echo "Building cc (Linux)..."
hbmk2 cc_linux.hbp "$@"
echo "Build successful: ./cc"
