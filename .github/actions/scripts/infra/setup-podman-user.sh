#!/usr/bin/env bash
# setup-podman-user.sh - Create and configure podman user for rootless containers
set -euo pipefail

PODMAN_USER="${PODMAN_USER:-deployer}"

echo "🔧 Ensuring podman user: $PODMAN_USER"
if id -u "$PODMAN_USER" >/dev/null 2>&1; then
  echo "👤 User $PODMAN_USER already exists"
else
  echo "➕ Creating user $PODMAN_USER"
  useradd -m -s /bin/bash "$PODMAN_USER"
fi

echo "🔐 Granting passwordless sudo to $PODMAN_USER"
echo "$PODMAN_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$PODMAN_USER >/dev/null

echo "🕒 Enabling linger and user podman.socket for rootless containers"
loginctl enable-linger "$PODMAN_USER" || true
PUID=$(id -u "$PODMAN_USER")
runuser -l "$PODMAN_USER" -c "XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user enable --now podman.socket" || true

echo "✅ Podman user $PODMAN_USER configured"
echo "🔎 id $PODMAN_USER"
id "$PODMAN_USER"
