#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# setup-traefik.sh - User-level Traefik configuration and container launch
# ----------------------------------------------------------------------------
# Purpose:
#   Configure and launch Traefik container as podman user.
#   Enables user Podman socket, determines socket path, reuses existing config,
#   checks for port conflicts, optionally exposes dashboard, and ensures
#   persistence via systemd user services.
#   Assumes system installation already completed by install-traefik.sh.
#
# Inputs (environment variables):
#   TRAEFIK_EMAIL          - Email for Let's Encrypt account (required when ACME enabled)
#   TRAEFIK_VERSION        - Traefik image tag (default: v3.5.4)
#   TRAEFIK_ENABLE_ACME    - "true" to request certificates via ACME (default: true)
#   TRAEFIK_PING_ENABLED   - "true" to expose ping healthcheck endpoint (default: true)
#   TRAEFIK_DASHBOARD      - "true" to expose dashboard on port 8080 (default: false)
#   DASHBOARD_USER         - Basic auth username (required if dashboard enabled)
#   DASHBOARD_PASS_BCRYPT  - Bcrypt hash for dashboard user (required if dashboard enabled)
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Resolve inputs -----------------------------------------------------------------
# Get required environment variables with defaults
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.5.4}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-true}"
TRAEFIK_PING_ENABLED="${TRAEFIK_PING_ENABLED:-true}"
TRAEFIK_DASHBOARD="${TRAEFIK_DASHBOARD:-false}"
DASHBOARD_USER="${DASHBOARD_USER:-}"
DASHBOARD_PASS_BCRYPT="${DASHBOARD_PASS_BCRYPT:-}"

# Validate required inputs
if [[ "$TRAEFIK_ENABLE_ACME" == "true" && -z "$TRAEFIK_EMAIL" ]]; then
  echo "Error: TRAEFIK_EMAIL is required when TRAEFIK_ENABLE_ACME=true" >&2
  exit 1
fi

if [[ "$TRAEFIK_DASHBOARD" == "true" ]]; then
  if [[ -z "$DASHBOARD_USER" || -z "$DASHBOARD_PASS_BCRYPT" ]]; then
    echo "Error: DASHBOARD_USER and DASHBOARD_PASS_BCRYPT are required when TRAEFIK_DASHBOARD=true" >&2
    exit 1
  fi
fi

# --- Preconditions ------------------------------------------------------------------
echo "🔎 Checking for podman ..."
if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is not installed on the host" >&2
  exit 1
fi

# Verify system installation was completed
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENSURE_CONFIG="$SCRIPT_DIR/ensure-traefik-config.sh"
if [[ -x "$ENSURE_CONFIG" ]]; then
  echo "🔍 Ensuring Traefik configuration files exist ..."
  "$ENSURE_CONFIG"
else
  echo "::warning::ensure-traefik-config.sh missing; skipping config reuse check" >&2
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
  echo "🔌 User podman socket unavailable; using root podman socket: $HOST_SOCK"
  echo "::notice::If this is unexpected, ensure linger is enabled and podman.socket is running for $CURRENT_USER."
fi

echo "🔍 Checking for existing listeners on ports 80/443 ..."
CONFLICTING_SERVICES="$(ss -ltnp 2>/dev/null | awk '/:(80|443) / {print $0}' || true)"
if [[ -n "$CONFLICTING_SERVICES" ]]; then
  echo "❌ ERROR: Detected services already listening on 80/443:" >&2
  printf '%s\n' "$CONFLICTING_SERVICES" >&2
  echo "   Stop or reconfigure the conflicting service before continuing." >&2
  exit 1
else
  echo "  ✓ No conflicting listeners detected"
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
RUN_ARGS=(
  podman run -d
  --name traefik
  --restart unless-stopped
  -p 80:80
  -p 443:443
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
  -v /var/lib/traefik/acme.json:/letsencrypt/acme.json
  -v "$HOST_SOCK":/var/run/docker.sock
  -e TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80
  -e TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443
)

if [[ "$TRAEFIK_ENABLE_ACME" == "true" ]]; then
  RUN_ARGS+=(
    -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure
    -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https
  )
else
  echo "::notice::ACME disabled; HTTP traffic will be served without redirect to HTTPS."
fi

if [[ "$TRAEFIK_PING_ENABLED" == "true" ]]; then
  RUN_ARGS+=(--ping=true -e TRAEFIK_PING_ENTRYPOINT=web)
fi

if [[ "$TRAEFIK_DASHBOARD" == "true" ]]; then
  echo "📊 Enabling Traefik dashboard on port 8080"
  RUN_ARGS+=(
    -p 8080:8080
    -e TRAEFIK_API_ENABLED=true
    -e TRAEFIK_API=true
    -e TRAEFIK_API_DASHBOARD=true
    -e TRAEFIK_API_DEBUG=true
    -e TRAEFIK_API_INSECURE=false
    -e TRAEFIK_ENTRYPOINTS_DASHBOARD_ADDRESS=:8080
    -e TRAEFIK_ENTRYPOINTS_DASHBOARD_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure
    -e TRAEFIK_ENTRYPOINTS_DASHBOARD_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https
    -e TRAEFIK_API_BASIC_AUTH_USERS="${DASHBOARD_USER}:${DASHBOARD_PASS_BCRYPT}"
  )
fi

if ! "${RUN_ARGS[@]}" docker.io/traefik:"${TRAEFIK_VERSION}"; then
  echo "Failed to start Traefik container" >&2
  podman logs traefik 2>&1 || true
  exit 1
fi

# --- Post status ---------------------------------------------------------------------
echo "✅ Traefik container started (image: docker.io/traefik:${TRAEFIK_VERSION})"
if [[ "$TRAEFIK_DASHBOARD" == "true" ]]; then
  echo "::notice::Traefik dashboard available at https://$(hostname -f 2>/dev/null || echo '<host>'):8080"
fi
echo "🔎 podman ps --filter name=traefik"
podman ps --filter name=traefik

echo "🧾 Generating systemd user service for Traefik ..."
if podman generate systemd --new --files --name traefik >/dev/null 2>&1; then
  podman generate systemd --new --files --name traefik
  mkdir -p "$HOME/.config/systemd/user"
  if mv container-traefik.service "$HOME/.config/systemd/user/" 2>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user enable --now container-traefik.service
    echo "  ✓ Installed container-traefik.service and enabled persistence"
  else
    echo "::warning::Failed to install container-traefik.service; check permissions." >&2
  fi
else
  echo "::warning::podman generate systemd not available; skipping persistence." >&2
fi
