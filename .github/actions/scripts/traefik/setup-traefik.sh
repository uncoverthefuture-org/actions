#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup-traefik.sh - User-level Traefik configuration and container launch
# ----------------------------------------------------------------------------
# Purpose:
#   Configure and launch Traefik container as podman user.
#   Enables user Podman socket, determines socket path, starts Traefik.
#   Assumes system installation already completed by install-traefik.sh.
#
# Inputs (environment variables):
#   TRAEFIK_EMAIL     - Email for Let's Encrypt account (REQUIRED)
#   PODMAN_USER       - Linux user that runs containers (default: deployer)
#   TRAEFIK_VERSION   - Traefik image tag (default: v3.1)
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Resolve inputs -----------------------------------------------------------------
# Get required environment variables with defaults
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
PODMAN_USER="${PODMAN_USER:-deployer}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.1}"

# Validate required inputs
if [[ -z "$TRAEFIK_EMAIL" ]]; then
  echo "Error: TRAEFIK_EMAIL is required" >&2
  exit 1
fi

# --- Preconditions ------------------------------------------------------------------
echo "🔎 Checking for podman ..."
if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is not installed on the host" >&2
  exit 1
fi

# Verify system installation was completed
echo "🔍 Verifying Traefik system installation ..."
if [ ! -f "/etc/traefik/traefik.yml" ]; then
  echo "Error: Traefik config not found. Run install-traefik.sh first (requires sudo access)." >&2
  exit 1
fi

if [ ! -f "/var/lib/traefik/acme.json" ]; then
  echo "Error: ACME storage not found. Run install-traefik.sh first (requires sudo access)." >&2
  exit 1
fi

# Check if deployer user can bind to low ports (required for Traefik)
echo "🔍 Checking if $PODMAN_USER can bind to low ports (80/443) ..."
if ! runuser -l "$PODMAN_USER" -c "timeout 5 bash -c 'exec 3<>/dev/tcp/localhost/80' 2>/dev/null || true" 2>/dev/null && \
   ! runuser -l "$PODMAN_USER" -c "python3 -c 'import socket; s=socket.socket(); s.bind((\"\", 80)); s.close()' 2>/dev/null" 2>/dev/null; then
  echo "❌ ERROR: User $PODMAN_USER cannot bind to port 80." >&2
  echo "   Traefik must run in the same user namespace as containers ($PODMAN_USER)." >&2
  echo "   To fix this:" >&2
  echo "   1. Grant CAP_NET_BIND_SERVICE to podman: sudo setcap cap_net_bind_service=+ep \$(which podman)" >&2
  echo "   2. Or use authbind: sudo apt install authbind && sudo touch /etc/authbind/byport/80 /etc/authbind/byport/443 && sudo chown $PODMAN_USER /etc/authbind/byport/*" >&2
  exit 1
fi

# Helper to run podman as deployer user (follows project pattern)
run_podman() {
  if [ "$(id -un)" = "$PODMAN_USER" ]; then
    podman "$@"
  else
    sudo -H -u "$PODMAN_USER" podman "$@"
  fi
}

# --- Enable Podman user socket -------------------------------------------------------
echo "🧩 Enabling linger and Podman user socket for $PODMAN_USER ..."
PUID=$(id -u "$PODMAN_USER" 2>/dev/null || echo 1000)
# Check if linger is already enabled
if ! loginctl show-user "$PODMAN_USER" 2>/dev/null | grep -q "Linger=yes"; then
  loginctl enable-linger "$PODMAN_USER" >/dev/null 2>&1 || true
  echo "  ✓ Enabled linger for $PODMAN_USER"
else
  echo "  ✓ Linger already enabled for $PODMAN_USER"
fi
# Check if user podman socket is enabled and running
if ! runuser -l "$PODMAN_USER" -c "XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user is-active --quiet podman.socket" 2>/dev/null; then
  runuser -l "$PODMAN_USER" -c "XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user enable --now podman.socket" >/dev/null 2>&1 || true
  echo "  ✓ Enabled and started podman.socket for $PODMAN_USER"
else
  echo "  ✓ podman.socket already running for $PODMAN_USER"
fi

USER_RUNTIME_DIR="/run/user/$PUID"
SOCK_USER="$USER_RUNTIME_DIR/podman/podman.sock"
SOCK_ROOT="/var/run/podman/podman.sock"
if [[ -S "$SOCK_USER" ]]; then
  HOST_SOCK="$SOCK_USER"
  echo "🔌 Using user podman socket: $HOST_SOCK"
else
  HOST_SOCK="$SOCK_ROOT"
  echo "🔌 Using root podman socket: $HOST_SOCK"
fi

# --- Container management -------------------------------------------------------------
echo "🛑 Stopping existing Traefik container (if any) ..."
if run_podman container exists traefik >/dev/null 2>&1; then
  run_podman stop traefik >/dev/null 2>&1 || true
  echo "  ✓ Stopped existing traefik container"
else
  echo "  ✓ No existing traefik container to stop"
fi

echo "🧹 Removing existing Traefik container (if any) ..."
if run_podman container exists traefik >/dev/null 2>&1; then
  run_podman rm traefik >/dev/null 2>&1 || true
  echo "  ✓ Removed existing traefik container"
else
  echo "  ✓ No existing traefik container to remove"
fi

echo "🚀 Starting Traefik container (version: ${TRAEFIK_VERSION}) ..."
if ! run_podman run -d \
  --name traefik \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
  -v /var/lib/traefik/acme.json:/letsencrypt/acme.json \
  -v "$HOST_SOCK":/var/run/docker.sock \
  docker.io/traefik:"${TRAEFIK_VERSION}"; then
  echo "Failed to start Traefik container" >&2
  run_podman logs traefik 2>&1 || true
  exit 1
fi

# --- Post status ---------------------------------------------------------------------
echo "✅ Traefik container started (image: docker.io/traefik:${TRAEFIK_VERSION})"
echo "🔎 podman ps --filter name=traefik"
run_podman ps --filter name=traefik
