#!/usr/bin/env bash
# setup-podman-user.sh - Create and configure podman user for rootless containers
set -euo pipefail

PODMAN_USER="${PODMAN_USER:-deployer}"

echo "🔧 Ensuring podman user: $PODMAN_USER"
IS_ROOT="no"
if [ "$(id -u)" -eq 0 ]; then IS_ROOT="yes"; fi
SUDO=""
if [ "$IS_ROOT" = "no" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi
if [ "$IS_ROOT" = "no" ] && [ -z "$SUDO" ]; then
  echo '::error::Configuring a podman user requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Manual steps (as root):' >&2
  echo "  useradd -m -s /bin/bash '$PODMAN_USER'" >&2
  echo "  echo '$PODMAN_USER ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$PODMAN_USER" >&2
  echo "  loginctl enable-linger '$PODMAN_USER'" >&2
  echo "  PUID=$(id -u '$PODMAN_USER'); runuser -l '$PODMAN_USER' -c 'XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user enable --now podman.socket'" >&2
  exit 1
fi

if id -u "$PODMAN_USER" >/dev/null 2>&1; then
  echo "👤 User $PODMAN_USER already exists"
else
  echo "➕ Creating user $PODMAN_USER"
  $SUDO useradd -m -s /bin/bash "$PODMAN_USER"
fi

echo "🔐 Granting passwordless sudo to $PODMAN_USER"
echo "$PODMAN_USER ALL=(ALL) NOPASSWD:ALL" | $SUDO tee /etc/sudoers.d/$PODMAN_USER >/dev/null

echo "🕒 Enabling linger and user podman.socket for rootless containers"
${SUDO} loginctl enable-linger "$PODMAN_USER" || true
PUID=$(id -u "$PODMAN_USER")
${SUDO} runuser -l "$PODMAN_USER" -c "XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user enable --now podman.socket" || true

echo "✅ Podman user $PODMAN_USER configured"
echo "🔎 id $PODMAN_USER"
id "$PODMAN_USER"
