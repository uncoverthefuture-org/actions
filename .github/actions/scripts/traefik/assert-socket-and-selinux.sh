#!/usr/bin/env bash
set -euo pipefail

CURRENT_USER="$(id -un)"
PUID="$(id -u)"
USER_RUNTIME_DIR="/run/user/${PUID}"
USER_SOCK="${USER_RUNTIME_DIR}/podman/podman.sock"
SYSTEM_SOCK="/var/run/podman/podman.sock"

# Try to enable linger (best effort)
if command -v loginctl >/dev/null 2>&1; then
  if ! loginctl show-user "$CURRENT_USER" 2>/dev/null | grep -q "Linger=yes"; then
    loginctl enable-linger "$CURRENT_USER" >/dev/null 2>&1 || true
  fi
fi

# Ensure podman user socket is active
if command -v systemctl >/dev/null 2>&1; then
  XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" systemctl --user enable --now podman.socket >/dev/null 2>&1 || true
fi

SOCK_PATH="$SYSTEM_SOCK"
if [ "$CURRENT_USER" != "root" ] && [ -S "$USER_SOCK" ]; then
  SOCK_PATH="$USER_SOCK"
fi

echo "Socket path: ${SOCK_PATH}"
if [ ! -S "$SOCK_PATH" ]; then
  echo "::warning::Podman socket not found at ${SOCK_PATH}. Ensure podman.socket is active for user ${CURRENT_USER}." >&2
fi

# SELinux mode (advisory)
SELINUX_MODE="unknown"
if command -v getenforce >/dev/null 2>&1; then
  SELINUX_MODE="$(getenforce 2>/dev/null || echo unknown)"
fi

echo "SELinux: ${SELINUX_MODE}"
if [ "$SELINUX_MODE" = "Enforcing" ]; then
  echo "::notice::On SELinux enforcing hosts, mount sockets/volumes with ':Z' and consider SecurityLabelDisable=true when using quadlets." >&2
fi

exit 0
