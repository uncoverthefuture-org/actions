#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup-traefik.sh
# ----------------------------------------------------------------------------
# Purpose:
#   Idempotently install and run Traefik (via Podman) on a host.
#   - Writes /etc/traefik/traefik.yml with Let's Encrypt HTTP-01
#   - Ensures podman user socket is available so Traefik can discover containers
#   - Stops/removes any existing 'traefik' container
#   - Starts new Traefik container exposing 80/443 and mounting podman socket
#
# Inputs (environment variables):
#   TRAEFIK_EMAIL     - Email for Let's Encrypt account (REQUIRED)
#   PODMAN_USER       - Linux user that runs application containers (default: deployer)
#   TRAEFIK_VERSION   - Traefik image tag (default: v3.1)
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail

# --- Resolve inputs -----------------------------------------------------------------
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
PODMAN_USER="${PODMAN_USER:-deployer}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.1}"

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

# Stop legacy proxies that might occupy 80/443 (ignore errors)
echo "🧹 Stopping legacy proxies (apache2, nginx) if present ..."
sudo systemctl stop apache2 nginx >/dev/null 2>&1 || true
sudo systemctl disable apache2 nginx >/dev/null 2>&1 || true

# --- Filesystem layout ---------------------------------------------------------------
echo "📁 Ensuring Traefik directories exist ..."
sudo mkdir -p /etc/traefik
sudo mkdir -p /var/lib/traefik

echo "📝 Writing Traefik config to /etc/traefik/traefik.yml ..."
sudo tee /etc/traefik/traefik.yml >/dev/null <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  podman:
    # Traefik will be given access to the Podman API socket via /var/run/docker.sock
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

echo "🔐 Preparing ACME storage ..."
sudo touch /var/lib/traefik/acme.json
sudo chmod 600 /var/lib/traefik/acme.json

# Change ownership of Traefik directories to podman user
echo "👤 Changing ownership of Traefik directories to $PODMAN_USER ..."
sudo chown -R "$PODMAN_USER:$PODMAN_USER" /etc/traefik /var/lib/traefik

# --- Determine Podman API socket to mount -------------------------------------------
echo "🧩 Enabling linger and Podman user socket for $PODMAN_USER ..."
PUID=$(id -u "$PODMAN_USER" 2>/dev/null || echo 1000)
# Ensure user linger and user socket so rootless containers are discoverable
loginctl enable-linger "$PODMAN_USER" >/dev/null 2>&1 || true
runuser -l "$PODMAN_USER" -c "XDG_RUNTIME_DIR=/run/user/$PUID systemctl --user enable --now podman.socket" >/dev/null 2>&1 || true

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

echo "🛑 Stopping existing Traefik container (if any) ..."
runuser -l "$PODMAN_USER" -c "podman container exists traefik >/dev/null 2>&1 && podman stop traefik >/dev/null 2>&1" || true
echo "🧹 Removing existing Traefik container (if any) ..."
runuser -l "$PODMAN_USER" -c "podman container exists traefik >/dev/null 2>&1 && podman rm traefik >/dev/null 2>&1" || true

echo "🚀 Starting Traefik container (version: ${TRAEFIK_VERSION}) ..."
if ! runuser -l "$PODMAN_USER" -c "podman run -d \
  --name traefik \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
  -v /var/lib/traefik/acme.json:/letsencrypt/acme.json \
  -v \"$HOST_SOCK\":/var/run/docker.sock \
  docker.io/traefik:\"${TRAEFIK_VERSION}\""; then
  echo "Failed to start Traefik container" >&2
  runuser -l "$PODMAN_USER" -c "podman logs traefik" 2>&1 || true
  exit 1
fi

# --- Post status ---------------------------------------------------------------------
echo "✅ Traefik container started (image: docker.io/traefik:${TRAEFIK_VERSION})"
echo "🔎 podman ps --filter name=traefik"
runuser -l "$PODMAN_USER" -c "podman ps --filter name=traefik"
