#!/usr/bin/env bash
# install-podman.sh - Install Podman and dependencies on Ubuntu/Debian
set -euo pipefail

ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-}"

echo "🔧 Starting Podman installation ..."
if [ -n "$ADDITIONAL_PACKAGES" ]; then
  echo "📦 Additional packages requested: $ADDITIONAL_PACKAGES"
else
  echo "📦 No additional packages requested"
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "📥 Updating apt cache ..."
  # Allow noninteractive installs to continue when trusted repositories update
  # their Release metadata (for example, changing the Label or Suite fields).
  apt-get update -y --allow-releaseinfo-change
  echo "📦 Installing Podman and dependencies ..."
  apt-get install -y podman uidmap slirp4netns fuse-overlayfs ${ADDITIONAL_PACKAGES}
else
  echo 'Error: Only Debian/Ubuntu apt-based systems are supported' >&2
  exit 1
fi

echo "✅ Podman installed successfully"
echo "🔎 podman --version"
podman --version
