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
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-traefik-network}"
TRAEFIK_USE_HOST_NETWORK="${TRAEFIK_USE_HOST_NETWORK:-false}"
TRAEFIK_ENABLE_METRICS="${TRAEFIK_ENABLE_METRICS:-false}"
TRAEFIK_METRICS_ENTRYPOINT="${TRAEFIK_METRICS_ENTRYPOINT:-metrics}"
TRAEFIK_METRICS_ADDRESS="${TRAEFIK_METRICS_ADDRESS:-:8082}"
TRAEFIK_ACME_DNS_PROVIDER="${TRAEFIK_ACME_DNS_PROVIDER:-}"
TRAEFIK_ACME_DNS_RESOLVERS="${TRAEFIK_ACME_DNS_RESOLVERS:-}"
TRAEFIK_DNS_SERVERS="${TRAEFIK_DNS_SERVERS:-}"
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
CAN_BIND=false
if timeout 3 bash -c 'exec 3<>/dev/tcp/localhost/80' 2>/dev/null || \
   python3 -c 'import socket; s=socket.socket(); s.bind(("", 80)); s.close()' 2>/dev/null; then
  CAN_BIND=true
fi

CURRENT_USER_LOG="$(id -un) (uid:$(id -u))"
SUDO_AVAILABLE=no
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO_AVAILABLE=yes; fi
echo "👤 User: ${CURRENT_USER_LOG}; sudo: ${SUDO_AVAILABLE}"
if command -v getcap >/dev/null 2>&1; then
  echo "🔐 getcap $(command -v podman): $(getcap "$(command -v podman)" 2>/dev/null || true)"
fi

if [ "$CAN_BIND" != "true" ]; then
  echo "::notice::Current user cannot bind to port 80 directly. Traefik may still work via rootless port forwarding."
  if [ "$SUDO_AVAILABLE" = "yes" ]; then
    echo "::notice::Attempting to grant CAP_NET_BIND_SERVICE to podman via sudo setcap ..."
    if sudo setcap cap_net_bind_service=+ep "$(command -v podman)" 2>/dev/null; then
      echo "  ✓ setcap applied to podman"
      if command -v getcap >/dev/null 2>&1; then
        echo "🔐 getcap $(command -v podman): $(getcap "$(command -v podman)" 2>/dev/null || true)"
      fi
    else
      echo "::warning::Failed to apply setcap; consider authbind or allowing low ports (net.ipv4.ip_unprivileged_port_start=80)."
    fi
  else
    echo "::notice::sudo not available; consider authbind or enabling low ports for rootless."
  fi
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
if [[ "$CURRENT_USER" == "root" ]]; then
  HOST_SOCK="$SOCK_ROOT"
  echo "🔌 Running as root; using system podman socket: $HOST_SOCK"
else
  if [[ -S "$SOCK_USER" ]]; then
    HOST_SOCK="$SOCK_USER"
    echo "🔌 Using user podman socket: $HOST_SOCK"
  else
    HOST_SOCK="$SOCK_ROOT"
    echo "🔌 User podman socket unavailable; using system podman socket: $HOST_SOCK"
    echo "::notice::If this is unexpected, ensure linger is enabled and podman.socket is running for $CURRENT_USER."
  fi
fi

if [[ -x "/opt/uactions/scripts/traefik/assert-socket-and-selinux.sh" ]]; then
  /opt/uactions/scripts/traefik/assert-socket-and-selinux.sh
fi

echo "🔍 Checking for existing listeners on ports 80/443 ..."
CONFLICTING_SERVICES="$(ss -ltnp 2>/dev/null | awk '/:(80|443) / {print $0}' || true)"
if [[ -n "$CONFLICTING_SERVICES" ]]; then
  echo "⚠️  Detected listeners on 80/443; attempting to stop existing 'traefik' container if running ..." >&2
  if podman container exists traefik >/dev/null 2>&1; then
    podman stop traefik >/dev/null 2>&1 || true
    podman rm traefik   >/dev/null 2>&1 || true
    echo "  ✓ Stopped and removed existing traefik container"
  fi
  # Re-check after attempting to stop existing Traefik
  CONFLICTING_SERVICES="$(ss -ltnp 2>/dev/null | awk '/:(80|443) / {print $0}' || true)"
  if [[ -n "$CONFLICTING_SERVICES" ]]; then
    echo "❌ ERROR: Detected services still listening on 80/443:" >&2
    printf '%s\n' "$CONFLICTING_SERVICES" >&2
    echo "   Stop or reconfigure the conflicting service before continuing." >&2
    exit 1
  else
    echo "  ✓ Ports 80/443 are free after stopping existing traefik"
  fi
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
)

if [[ -n "$TRAEFIK_NETWORK_NAME" ]]; then
  if ! podman network exists "$TRAEFIK_NETWORK_NAME" >/dev/null 2>&1; then
    echo "🌐 Creating Podman network: $TRAEFIK_NETWORK_NAME"
    podman network create "$TRAEFIK_NETWORK_NAME"
  else
    echo "🌐 Podman network already exists: $TRAEFIK_NETWORK_NAME"
  fi
fi

if [[ "$TRAEFIK_USE_HOST_NETWORK" == "true" ]]; then
  echo "🌐 Using host network for Traefik"
  RUN_ARGS+=(--network host)
else
  RUN_ARGS+=(-p 80:80 -p 443:443)
  if [[ -n "$TRAEFIK_NETWORK_NAME" ]]; then
    RUN_ARGS+=(--network "$TRAEFIK_NETWORK_NAME")
  fi
fi

# Optional: set DNS servers for container to avoid resolution timeouts
if [[ -n "$TRAEFIK_DNS_SERVERS" ]]; then
  # Support comma or space separated list
  IFS=', ' read -r -a _DNS_ARR <<< "$TRAEFIK_DNS_SERVERS"
  for _dns in "${_DNS_ARR[@]}"; do
    if [[ -n "$_dns" ]]; then
      RUN_ARGS+=(--dns "$_dns")
    fi
  done
fi

RUN_ARGS+=(-v "$HOME/.config/traefik/traefik.yml":/etc/traefik/traefik.yml:ro)
RUN_ARGS+=(-v "$HOME/.local/share/traefik/acme.json":/letsencrypt/acme.json:Z)
RUN_ARGS+=(-v "$HOST_SOCK":/var/run/docker.sock:Z)
RUN_ARGS+=(-e TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80)
RUN_ARGS+=(-e TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443)

if [[ "$TRAEFIK_ENABLE_ACME" == "true" ]]; then
  RUN_ARGS+=(
    -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure
    -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https
    -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL="$TRAEFIK_EMAIL"
    -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/letsencrypt/acme.json
    -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE_ENTRYPOINT=web
    -e TRAEFIK_ENTRYPOINTS_WEBSECURE_HTTP_TLS_CERTRESOLVER=letsencrypt
  )
  if [[ -n "$TRAEFIK_ACME_DNS_PROVIDER" ]]; then
    RUN_ARGS+=(-e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER="$TRAEFIK_ACME_DNS_PROVIDER")
    if [[ -n "$TRAEFIK_ACME_DNS_RESOLVERS" ]]; then
      RUN_ARGS+=(-e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS="${TRAEFIK_ACME_DNS_RESOLVERS//,/\,}")
    fi
  fi
else
  echo "::notice::ACME disabled; HTTP traffic will be served without redirect to HTTPS."
fi

if [[ "$TRAEFIK_PING_ENABLED" == "true" ]]; then
  RUN_ARGS+=(-e TRAEFIK_PING=true -e TRAEFIK_PING_ENTRYPOINT=web)
fi

if [[ "$TRAEFIK_DASHBOARD" == "true" ]]; then
  echo "📊 Enabling Traefik dashboard on port 8080"
  if [[ "$TRAEFIK_USE_HOST_NETWORK" != "true" ]]; then
    RUN_ARGS+=(-p 8080:8080)
  fi
  RUN_ARGS+=(
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

if [[ "$TRAEFIK_ENABLE_METRICS" == "true" ]]; then
  METRICS_PORT="${TRAEFIK_METRICS_ADDRESS##*:}"
  if [[ -z "$METRICS_PORT" ]]; then
    METRICS_PORT="8082"
  fi
  echo "📈 Enabling Prometheus metrics on entrypoint '${TRAEFIK_METRICS_ENTRYPOINT}' (${TRAEFIK_METRICS_ADDRESS})"
  RUN_ARGS+=(
    -e TRAEFIK_METRICS_PROMETHEUS=true
    -e TRAEFIK_METRICS_PROMETHEUS_ADDROUTERSLABELS=true
    -e TRAEFIK_METRICS_PROMETHEUS_ADDSERVICESLABELS=true
    -e TRAEFIK_METRICS_PROMETHEUS_ENTRYPOINT="${TRAEFIK_METRICS_ENTRYPOINT}"
    -e TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS="${TRAEFIK_METRICS_ADDRESS}"
  )
  if [[ "$TRAEFIK_USE_HOST_NETWORK" != "true" ]]; then
    RUN_ARGS+=(-p "${METRICS_PORT}:${METRICS_PORT}")
  fi
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

echo "⏳ Waiting for Traefik listeners on ports 80/443 ..."
ok=false
for i in {1..10}; do
  if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$' && \
     ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then
    ok=true; break
  fi
  sleep 2
done
if ! $ok; then
  echo "::error::Traefik did not open ports 80/443 after start."
  podman logs --tail=120 traefik 2>/dev/null || true
  exit 1
fi

echo "🧾 Generating systemd user service for Traefik ..."
if podman generate systemd --files --name traefik >/dev/null 2>&1; then
  podman generate systemd --files --name traefik
  mkdir -p "$HOME/.config/systemd/user"
  if mv container-traefik.service "$HOME/.config/systemd/user/" 2>/dev/null; then
    if systemctl --user daemon-reload >/dev/null 2>&1; then
      if systemctl --user enable --now container-traefik.service >/dev/null 2>&1; then
        echo "  ✓ Installed container-traefik.service and enabled persistence"
      else
        echo "::warning::Failed to enable/start container-traefik.service (user systemd may be unavailable)." >&2
      fi
    else
      echo "::warning::systemctl --user daemon-reload failed; user-level systemd may be unavailable." >&2
    fi
  else
    echo "::warning::Failed to install container-traefik.service; check permissions." >&2
  fi
else
  echo "::warning::podman generate systemd not available; skipping persistence." >&2
fi
