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
  
  # Attempt update; if it fails, check if we are on an EOL Ubuntu version and recover repositories
  if ! apt-get update -y --allow-releaseinfo-change; then
    echo "⚠️  apt-get update failed. Checking for EOL Ubuntu repositories..."
    if grep -q "ubuntu" /etc/os-release 2>/dev/null; then
      echo "🛠️  Detected Ubuntu; attempting to point sources to old-releases.ubuntu.com..."
      sudo sed -i 's/http:\/\/.*\.ubuntu\.com\/ubuntu\//http:\/\/old-releases.ubuntu.com\/ubuntu\//g' /etc/apt/sources.list || true
      sudo sed -i 's/http:\/\/security\.ubuntu\.com\/ubuntu\//http:\/\/old-releases.ubuntu.com\/ubuntu\//g' /etc/apt/sources.list || true
      
      echo "🔄 Retrying apt-get update with archive mirrors..."
      if ! apt-get update -y --allow-releaseinfo-change; then
        echo "❌ Error: Failed to update apt cache even with archive mirrors." >&2
        exit 1
      fi
      echo "✅ Successfully recovered repositories via old-releases archive."
    else
      echo "❌ Error: apt-get update failed and OS is not recognized as Ubuntu." >&2
      exit 1
    fi
  fi
  
  echo "📦 Installing Podman and dependencies ..."
  apt-get install -y podman uidmap slirp4netns fuse-overlayfs ${ADDITIONAL_PACKAGES}
else
  echo 'Error: Only Debian/Ubuntu apt-based systems are supported' >&2
  exit 1
fi

echo "✅ Podman installed successfully"
echo "🔎 podman --version"
podman --version
