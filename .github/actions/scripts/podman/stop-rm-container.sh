#!/usr/bin/env bash
# stop-rm-container.sh - Stop and remove a Podman container
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-}"

if [ -z "$CONTAINER_NAME" ]; then
  echo "Error: CONTAINER_NAME is required" >&2
  exit 1
fi

# Helper to run podman as deployer user
run_podman() {
  if [ "$(id -un)" = "deployer" ]; then
    podman "$@"
  else
    sudo -H -u deployer podman "$@"
  fi
}

echo "🔧 Preparing to stop and remove container"
echo "  • Target: $CONTAINER_NAME"

echo "🛑 Stopping container (if running): $CONTAINER_NAME"
run_podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing container (if exists): $CONTAINER_NAME"
run_podman rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "✅ Container $CONTAINER_NAME stopped and removed"
