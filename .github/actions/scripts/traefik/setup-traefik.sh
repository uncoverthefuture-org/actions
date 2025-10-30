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

echo "🔍 Checking if current user can bind to low ports (80/443) ..."
if ! timeout 5 bash -c 'exec 3<>/dev/tcp/localhost/80' 2>/dev/null && \
   ! python3 -c 'import socket; s=socket.socket(); s.bind(("", 80)); s.close()' 2>/dev/null; then
  echo "❌ ERROR: Current user cannot bind to port 80." >&2
  echo "   Traefik requires CAP_NET_BIND_SERVICE or authbind." >&2
  echo "   To fix this:" >&2
  echo "   1. Grant CAP_NET_BIND_SERVICE to podman: sudo setcap cap_net_bind_service=+ep \$(which podman)" >&2
  echo "   2. Or use authbind: sudo apt install authbind && sudo touch /etc/authbind/byport/80 /etc/authbind/byport/443 && sudo chown \$(id -un) /etc/authbind/byport/*" >&2
  exit 1
fi

echo "🧩 Enabling linger and Podman user socket for current user ..."
CURRENT_USER="$(id -un)"
PUID="$(id -u)"
# Check if linger is already enabled
if ! loginctl show-user "$CURRENT_USER" 2>/dev/null | grep -q "Linger=yes"; then
  loginctl enable-linger "$CURRENT_USER" >/dev/null 2>&1 || true
  echo "  ✓ Enabled linger for $CURRENT_USER"
else
  echo "  ✓ Linger already enabled for $CURRENT_USER"
fi
# Check if user podman socket is enabled and running
if ! XDG_RUNTIME_DIR="/run/user/$PUID" systemctl --user is-active --quiet podman.socket 2>/dev/null; then
  XDG_RUNTIME_DIR="/run/user/$PUID" systemctl --user enable --now podman.socket >/dev/null 2>&1 || true
  echo "  ✓ Enabled and started podman.socket for $CURRENT_USER"
else
  echo "  ✓ podman.socket already running for $CURRENT_USER"
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
if podman container exists traefik >/dev/null 2>&1; then
  podman stop traefik >/dev/null 2>&1 || true
  echo "  ✓ Stopped existing traefik container"
else
  echo "  ✓ No existing traefik container to stop"
fi

echo "🧹 Removing existing Traefik container (if any) ..."
if podman container exists traefik >/dev/null 2>&1; then
  podman rm traefik >/dev/null 2>&1 || true
  echo "  ✓ Removed existing traefik container"
else
  echo "  ✓ No existing traefik container to remove"
fi

echo "🚀 Starting Traefik container (version: ${TRAEFIK_VERSION}) ..."
if ! podman run -d \
  --name traefik \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
  -v /var/lib/traefik/acme.json:/letsencrypt/acme.json \
  -v "$HOST_SOCK":/var/run/docker.sock \
  docker.io/traefik:"${TRAEFIK_VERSION}"; then
  echo "Failed to start Traefik container" >&2
  podman logs traefik 2>&1 || true
  exit 1
fi

# --- Post status ---------------------------------------------------------------------
echo "✅ Traefik container started (image: docker.io/traefik:${TRAEFIK_VERSION})"
echo "🔎 podman ps --filter name=traefik"
podman ps --filter name=traefik
