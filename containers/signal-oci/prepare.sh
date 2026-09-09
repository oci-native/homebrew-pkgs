#!/usr/bin/env bash
# Populate the build context: fetch the versioned signal .deb the
# Containerfile copies in. Args: <version> <context-dir>
set -euo pipefail
version=$1
dir=$2
curl -fsSL -o "$dir/signal-desktop.deb" \
  "https://updates.signal.org/desktop/apt/pool/s/signal-desktop/signal-desktop_${version}_amd64.deb"
