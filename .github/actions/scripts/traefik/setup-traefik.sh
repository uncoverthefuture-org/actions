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
#   TRAEFIK_DASHBOARD      - "true" to expose dashboard (deprecated; prefer DASHBOARD_PUBLISH_MODES)
#   DASHBOARD_PUBLISH_MODES- CSV: http8080, https8080, subdomain, or 'both' (https8080,subdomain)
#   DASHBOARD_HOST         - FQDN for subdomain mode (e.g., traefik.example.com)
#   DASHBOARD_USER         - Basic auth username (default: admin)
#   DASHBOARD_PASS_BCRYPT  - Pre-hashed password (htpasswd format). If empty, see below.
#   DASHBOARD_PASSWORD     - Plain password (script will hash; default: 12345678; prints warning)
#   DASHBOARD_USERS_B64    - Base64-encoded users file contents; overrides other credential inputs
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
DASHBOARD_PUBLISH_MODES="${DASHBOARD_PUBLISH_MODES:-}"
DASHBOARD_HOST="${DASHBOARD_HOST:-}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-}"
DASHBOARD_USERS_B64="${DASHBOARD_USERS_B64:-}"

# Validate required inputs
if [[ "$TRAEFIK_ENABLE_ACME" == "true" && -z "$TRAEFIK_EMAIL" ]]; then
  echo "Error: TRAEFIK_EMAIL is required when TRAEFIK_ENABLE_ACME=true" >&2
  exit 1
fi

if [[ "$TRAEFIK_DASHBOARD" == "true" && -z "$DASHBOARD_PUBLISH_MODES" ]]; then
  echo "::notice::TRAEFIK_DASHBOARD=true without DASHBOARD_PUBLISH_MODES; defaulting to 'http8080'" >&2
  DASHBOARD_PUBLISH_MODES="http8080"
fi

# --- Preconditions ------------------------------------------------------------------
echo "🔎 Checking for podman ..."
if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is not installed on the host" >&2
  exit 1
fi

# Verify system installation was completed and wire shared Traefik helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UTIL_TRAEFIK="$SCRIPT_DIR/../util/traefik.sh"
if [[ -r "$UTIL_TRAEFIK" ]]; then
  # Source shared Traefik helpers like cleanup_existing_traefik and
  # ensure_traefik_systemd_user_service so this script stays thin.
  # Example: after confirming listeners are healthy, call
  #   ensure_traefik_systemd_user_service
  # to persist Traefik via a user-level systemd unit.
  # shellcheck source=/dev/null
  . "$UTIL_TRAEFIK"
else
  echo "::error::Traefik utility helpers not found at $UTIL_TRAEFIK; cannot proceed." >&2
  exit 1
fi

ENSURE_CONFIG="$SCRIPT_DIR/ensure-traefik-config.sh"
if [[ -x "$ENSURE_CONFIG" ]]; then
  echo "🔍 Ensuring Traefik configuration files exist ..."
  "$ENSURE_CONFIG"
else
  echo "::warning::ensure-traefik-config.sh missing; skipping config reuse check" >&2
fi

echo "🔍 Checking if current user can bind to low ports (80/443) ..."
CAN_BIND=false
# Prefer inspecting the kernel's unprivileged port start so we don't confuse
# "can connect to port 80" with "can bind to port 80". On most Linux hosts,
# net.ipv4.ip_unprivileged_port_start defaults to 1024; when it is lowered to
# 80 or below, rootless processes may bind to 80/443 without additional hacks.
if command -v sysctl >/dev/null 2>&1; then
  unpriv_start=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo 1024)
  if [ "$unpriv_start" -le 80 ]; then
    CAN_BIND=true
  fi
fi

CURRENT_USER_LOG="$(id -un) (uid:$(id -u))"
SUDO_AVAILABLE=no
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO_AVAILABLE=yes; fi
echo "👤 User: ${CURRENT_USER_LOG}; sudo: ${SUDO_AVAILABLE}"
if command -v getcap >/dev/null 2>&1; then
  echo "🔐 getcap $(command -v podman): $(getcap "$(command -v podman)" 2>/dev/null || true)"
fi

# Prepare dashboard credentials early (before config hash) when dashboard is requested
DASH_ENABLED=false
if [[ "$TRAEFIK_DASHBOARD" == "true" || -n "$DASHBOARD_PUBLISH_MODES" ]]; then
  DASH_ENABLED=true
fi

DASH_AUTH_ENABLED=false
DASH_USERS_LOCAL_FILE=""
USED_DEFAULT_DASH_PASS=false

if $DASH_ENABLED; then
  # Decide destination path for users file
  if [ "$SUDO_AVAILABLE" = "yes" ]; then
    DASH_USERS_LOCAL_FILE="/etc/traefik/dashboard-users"
    sudo mkdir -p /etc/traefik >/dev/null 2>&1 || true
  else
    DASH_USERS_LOCAL_FILE="$HOME/.config/traefik/dashboard-users"
    mkdir -p "$HOME/.config/traefik" >/dev/null 2>&1 || true
  fi

  # If a pre-hashed users file is provided (base64), it wins
  if [[ -n "$DASHBOARD_USERS_B64" ]]; then
    if [ "$SUDO_AVAILABLE" = "yes" ] && [[ "$DASH_USERS_LOCAL_FILE" == /etc/traefik/* ]]; then
      printf '%s' "$DASHBOARD_USERS_B64" | base64 -d | sudo tee "$DASH_USERS_LOCAL_FILE" >/dev/null || true
    else
      printf '%s' "$DASHBOARD_USERS_B64" | base64 -d > "$DASH_USERS_LOCAL_FILE" 2>/dev/null || true
    fi
    DASH_AUTH_ENABLED=true
  else
    # Compose a users file line. Precedence: explicit bcrypt → plain password → default
    if [[ -n "$DASHBOARD_USER" && -n "$DASHBOARD_PASS_BCRYPT" ]]; then
      line="${DASHBOARD_USER}:${DASHBOARD_PASS_BCRYPT}"
    else
      : "${DASHBOARD_USER:=admin}"
      pass_src="$DASHBOARD_PASSWORD"
      if [[ -z "$pass_src" ]]; then
        pass_src="12345678"
        USED_DEFAULT_DASH_PASS=true
      fi
      if command -v htpasswd >/dev/null 2>&1; then
        # htpasswd -nB emits 'user:hash' on stdout
        line="$(htpasswd -nB "$DASHBOARD_USER" "$pass_src" 2>/dev/null | head -n1)"
      elif command -v openssl >/dev/null 2>&1; then
        line="${DASHBOARD_USER}:$(openssl passwd -apr1 "$pass_src")"
      else
        echo "::warning::Neither 'htpasswd' nor 'openssl' found; cannot create dashboard users file. Dashboard will be unsecured." >&2
        line=""
      fi
    fi
    if [[ -n "$line" ]]; then
      if [ "$SUDO_AVAILABLE" = "yes" ] && [[ "$DASH_USERS_LOCAL_FILE" == /etc/traefik/* ]]; then
        printf '%s\n' "$line" | sudo tee "$DASH_USERS_LOCAL_FILE" >/dev/null || true
      else
        printf '%s\n' "$line" > "$DASH_USERS_LOCAL_FILE" 2>/dev/null || true
      fi
      DASH_AUTH_ENABLED=true
    fi
  fi

  if $USED_DEFAULT_DASH_PASS; then
    echo "::warning::Traefik dashboard using default credentials admin/12345678. Change immediately via DASHBOARD_PASSWORD or DASHBOARD_USERS_B64."
  fi
fi

# Ensure setcap is available when sudo is present; needed for CAP_NET_BIND_SERVICE fallback
if [ "$SUDO_AVAILABLE" = "yes" ] && ! command -v setcap >/dev/null 2>&1; then
  echo "::notice::Installing libcap2-bin to provide setcap/getcap ..."
  # Use --allow-releaseinfo-change so apt cache refresh remains robust even if
  # repository Release metadata (for example, Label) changes between runs.
  sudo apt-get update -y --allow-releaseinfo-change >/dev/null 2>&1 || true
  sudo apt-get install -y libcap2-bin >/dev/null 2>&1 || true
fi

if [ "$CAN_BIND" != "true" ]; then
  echo "::notice::Current user cannot bind to port 80 directly. Traefik may still work via rootless port forwarding."
  if [ "$SUDO_AVAILABLE" = "yes" ]; then
    # First attempt: lower the unprivileged port start so rootless can open 80/443
    # This config persists via /etc/sysctl.d and is applied immediately; safe and reversible.
    echo "::notice::Attempting to allow unprivileged low ports via sysctl (net.ipv4.ip_unprivileged_port_start=80) ..."
    if sudo sh -c 'printf "net.ipv4.ip_unprivileged_port_start=80\n" > /etc/sysctl.d/99-uactions-unpriv-ports.conf' 2>/dev/null && \
       sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1 && \
       sudo sysctl --system >/dev/null 2>&1; then
      # Re-check bind capability after sysctl change
      CAN_BIND=false
      if timeout 3 bash -c 'exec 3<>/dev/tcp/localhost/80' 2>/dev/null || \
         python3 -c 'import socket; s=socket.socket(); s.bind(("", 80)); s.close()' 2>/dev/null; then
        CAN_BIND=true
      fi
      if [ "$CAN_BIND" = "true" ]; then
        echo "  ✓ Enabled unprivileged low ports; continuing with port publish 80/443"
      else
        echo "::warning::sysctl applied but bind test still failing; will try setcap fallback (may not help rootless publish)."
      fi
    else
      echo "::warning::Failed to apply sysctl for unprivileged ports; will try setcap fallback (may not help rootless publish)."
    fi
    # Last resort: grant CAP_NET_BIND_SERVICE to the podman binary.
    # Note: this may help host-network binds in some setups but does not bypass
    # rootless port publishing restrictions in slirp4netns.
    if [ "$CAN_BIND" != "true" ]; then
      echo "::notice::Attempting to grant CAP_NET_BIND_SERVICE to podman via sudo setcap ..."
      if sudo setcap cap_net_bind_service=+ep "$(command -v podman)" 2>/dev/null; then
        echo "  ✓ setcap applied to podman"
        if command -v getcap >/dev/null 2>&1; then
          echo "🔐 getcap $(command -v podman): $(getcap "$(command -v podman)" 2>/dev/null || true)"
        fi
      else
        echo "::warning::Failed to apply setcap; consider authbind or enabling low ports."
      fi
    fi
  else
    echo "::notice::sudo not available; consider authbind or asking an admin to set net.ipv4.ip_unprivileged_port_start=80."
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

if [[ -x "$HOME/uactions/scripts/traefik/assert-socket-and-selinux.sh" ]]; then
  "$HOME/uactions/scripts/traefik/assert-socket-and-selinux.sh"
fi

CFG_PATH="$HOME/.config/traefik/traefik.yml"
if command -v sha256sum >/dev/null 2>&1; then
  CFG_SHA="$(sha256sum "$CFG_PATH" 2>/dev/null | awk '{print $1}')"
else
  CFG_SHA="$(shasum -a 256 "$CFG_PATH" 2>/dev/null | awk '{print $1}')"
fi
: "${CFG_SHA:=missing}"
CONFIG_SRC="$(printf '%s\n' \
  "v:$TRAEFIK_VERSION" \
  "acme:$TRAEFIK_ENABLE_ACME:$TRAEFIK_EMAIL:$TRAEFIK_ACME_DNS_PROVIDER:$TRAEFIK_ACME_DNS_RESOLVERS" \
  "ping:$TRAEFIK_PING_ENABLED" \
  "dash:$TRAEFIK_DASHBOARD:$DASHBOARD_USER" \
  "dashm:${DASHBOARD_PUBLISH_MODES}:${DASHBOARD_HOST}" \
  "metrics:$TRAEFIK_ENABLE_METRICS:$TRAEFIK_METRICS_ENTRYPOINT:$TRAEFIK_METRICS_ADDRESS" \
  "net:$TRAEFIK_USE_HOST_NETWORK:$TRAEFIK_NETWORK_NAME" \
  "dns:$TRAEFIK_DNS_SERVERS" \
  "cfg:$CFG_SHA")"
if command -v sha256sum >/dev/null 2>&1; then
  CONFIG_HASH="$(printf '%s' "$CONFIG_SRC" | sha256sum | awk '{print $1}')"
else
  CONFIG_HASH="$(printf '%s' "$CONFIG_SRC" | shasum -a 256 | awk '{print $1}')"
fi

# Summarize desired config hash for visibility
echo "🔎 Desired Traefik confighash: ${CONFIG_HASH}"

if [[ "${TRAEFIK_FORCE_RESTART:-false}" = "true" ]]; then
  echo "::notice::TRAEFIK_FORCE_RESTART=true; bypassing reuse fast-path and recreating Traefik."
else
  if podman container exists traefik >/dev/null 2>&1; then
    EXIST_HASH="$(podman inspect -f '{{ index .Config.Labels "org.uactions.traefik.confighash" }}' traefik 2>/dev/null || true)"
    STATUS="$(podman inspect -f '{{.State.Status}}' traefik 2>/dev/null || true)"
    echo "🔎 Remote Traefik confighash: ${EXIST_HASH:-missing} (status: ${STATUS})"
    if [[ "$EXIST_HASH" = "$CONFIG_HASH" ]]; then
      if [[ "$STATUS" = "running" ]]; then
        if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$' && \
           ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then
          echo "✅ Traefik already running and up-to-date (confighash match); skipping restart."
          ensure_traefik_systemd_user_service
          exit 0
        else
          echo "::notice::Traefik confighash matches but listeners not detected; restarting container to recover ..."
          podman restart traefik >/dev/null 2>&1 || true
          ok=false
          for i in {1..10}; do
            if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$' && \
               ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then ok=true; break; fi
            sleep 2
          done
          if $ok; then
            echo "✅ Traefik recovered after restart; leaving container as-is."
            ensure_traefik_systemd_user_service
            exit 0
          else
            echo "::warning::Traefik restart did not restore listeners; will recreate container."
          fi
        fi
      else
        echo "::notice::Traefik container exists but status='${STATUS}'; attempting start ..."
        podman start traefik >/dev/null 2>&1 || true
        if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$' && \
           ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then
          echo "✅ Traefik started and listeners present; skipping recreate."
          ensure_traefik_systemd_user_service
          exit 0
        fi
        echo "::warning::Traefik start did not show listeners; will recreate container."
      fi
    else
      # Mismatch (or missing) confighash will lead to reconcile below
      echo "::notice::Traefik confighash differs (remote=${EXIST_HASH:-missing} → desired=${CONFIG_HASH}); proceeding to reconcile ..."
    fi
  fi
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
    if command -v systemctl >/dev/null 2>&1; then
      if [ "$(id -u)" -eq 0 ] || [ "$SUDO_AVAILABLE" = "yes" ]; then
        echo "⚠️  Detected services still listening on 80/443; attempting to stop apache2/nginx via systemctl ..." >&2
        if systemctl is-active --quiet apache2 2>/dev/null; then
          if [ "$(id -u)" -eq 0 ]; then
            systemctl stop apache2 || true
            systemctl disable apache2 >/dev/null 2>&1 || true
          else
            sudo systemctl stop apache2 || true
            sudo systemctl disable apache2 >/dev/null 2>&1 || true
          fi
        fi
        if systemctl is-active --quiet nginx 2>/dev/null; then
          if [ "$(id -u)" -eq 0 ]; then
            systemctl stop nginx || true
            systemctl disable nginx >/dev/null 2>&1 || true
          else
            sudo systemctl stop nginx || true
            sudo systemctl disable nginx >/dev/null 2>&1 || true
          fi
        fi
        CONFLICTING_SERVICES="$(ss -ltnp 2>/dev/null | awk '/:(80|443) / {print $0}' || true)"
      fi
    fi
    if [[ -n "$CONFLICTING_SERVICES" ]]; then
      echo "❌ ERROR: Detected services still listening on 80/443:" >&2
      printf '%s\n' "$CONFLICTING_SERVICES" >&2
      echo "   Stop or reconfigure the conflicting service before continuing." >&2
      exit 1
    else
      echo "  ✓ Ports 80/443 are free after stopping conflicting services"
    fi
  else
    echo "  ✓ Ports 80/443 are free after stopping existing traefik"
  fi
fi

# --- Container management -------------------------------------------------------------
echo "🛑 Ensuring no existing Traefik container ..."
if podman container exists traefik >/dev/null 2>&1; then
  cleanup_existing_traefik
  if podman container exists traefik >/dev/null 2>&1; then
    echo "::error::Failed to free container name 'traefik'; aborting." >&2
    exit 1
  else
    echo "  ✓ Existing traefik container fully removed"
  fi
else
  echo "  ✓ No existing traefik container present"
fi

echo "🚀 Starting Traefik container (version: ${TRAEFIK_VERSION}) ..."
RUN_ARGS=(
  podman run -d
  --name traefik
  --restart unless-stopped
)

# Use native replacement if supported
if podman run --help 2>&1 | grep -q -- '--replace'; then
  RUN_ARGS+=(--replace)
fi

# Avoid pull when image already exists locally
if podman image exists "docker.io/traefik:${TRAEFIK_VERSION}" >/dev/null 2>&1; then
  RUN_ARGS+=(--pull=never)
fi

if [[ -n "$TRAEFIK_NETWORK_NAME" ]]; then
  if ! podman network exists "$TRAEFIK_NETWORK_NAME" >/dev/null 2>&1; then
    echo "🌐 Creating Podman network: $TRAEFIK_NETWORK_NAME"
    podman network create "$TRAEFIK_NETWORK_NAME"
  else
    echo "🌐 Podman network already exists: $TRAEFIK_NETWORK_NAME"
  fi
  if command -v traefik_fix_cni_config_version >/dev/null 2>&1; then
    traefik_fix_cni_config_version "$TRAEFIK_NETWORK_NAME" "${DEBUG:-false}" || true
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
RUN_ARGS+=(--label org.uactions.managed-by=uactions --label "org.uactions.traefik.confighash=${CONFIG_HASH}")

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

if [[ "$TRAEFIK_DASHBOARD" == "true" || -n "$DASHBOARD_PUBLISH_MODES" ]]; then
  echo "📊 Enabling Traefik dashboard"
  # Normalize modes
  MODES_RAW="$DASHBOARD_PUBLISH_MODES"
  if [[ -z "$MODES_RAW" ]]; then MODES_RAW="http8080"; fi
  MODES_RAW="${MODES_RAW,,}"
  MODES_RAW="${MODES_RAW// /}"
  if [[ "$MODES_RAW" == "both" ]]; then MODES_RAW="https8080,subdomain"; fi
  IFS=',' read -r -a MODES <<< "$MODES_RAW"

  # Always enable API/dashboard features
  RUN_ARGS+=(
    -e TRAEFIK_API_ENABLED=true
    -e TRAEFIK_API=true
    -e TRAEFIK_API_DASHBOARD=true
    -e TRAEFIK_API_DEBUG=true
    -e TRAEFIK_API_INSECURE=false
  )

  # Prepare labels and mounts for BasicAuth
  DASH_LABELS=()
  if $DASH_AUTH_ENABLED && [[ -n "$DASH_USERS_LOCAL_FILE" ]]; then
    RUN_ARGS+=(-v "${DASH_USERS_LOCAL_FILE}:/etc/traefik/dashboard-users:Z")
    DASH_LABELS+=(--label 'traefik.http.middlewares.traefik-auth.basicauth.usersfile=/etc/traefik/dashboard-users')
  else
    echo "::warning::Dashboard is enabled without BasicAuth; consider providing DASHBOARD_PASSWORD or DASHBOARD_USERS_B64."
  fi

  # Iterate modes
  ADDED_TRAEFIK_ENTRYPOINT=false
  ADDED_8080_PUBLISH=false
  for m in "${MODES[@]}"; do
    case "$m" in
      http8080)
        # 8080 HTTP entrypoint
        if [[ "$TRAEFIK_USE_HOST_NETWORK" != "true" && "$ADDED_8080_PUBLISH" != "true" ]]; then
          RUN_ARGS+=(-p 8080:8080)
          ADDED_8080_PUBLISH=true
        fi
        if [[ "$ADDED_TRAEFIK_ENTRYPOINT" != "true" ]]; then
          RUN_ARGS+=(-e TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS=:8080)
          ADDED_TRAEFIK_ENTRYPOINT=true
        fi
        DASH_LABELS+=(--label 'traefik.enable=true')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.entrypoints=traefik')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.rule=PathPrefix("/")')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.service=api@internal')
        if $DASH_AUTH_ENABLED; then DASH_LABELS+=(--label 'traefik.http.routers.traefik.middlewares=traefik-auth@docker'); fi
        ;;
      https8080)
        if [[ "$TRAEFIK_USE_HOST_NETWORK" != "true" && "$ADDED_8080_PUBLISH" != "true" ]]; then
          RUN_ARGS+=(-p 8080:8080)
          ADDED_8080_PUBLISH=true
        fi
        if [[ "$ADDED_TRAEFIK_ENTRYPOINT" != "true" ]]; then
          RUN_ARGS+=(-e TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS=:8080)
          ADDED_TRAEFIK_ENTRYPOINT=true
        fi
        RUN_ARGS+=(-e TRAEFIK_ENTRYPOINTS_TRAEFIK_HTTP_TLS=true)
        DASH_LABELS+=(--label 'traefik.enable=true')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.entrypoints=traefik')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.rule=PathPrefix("/")')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.service=api@internal')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.tls=true')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik.tls.certresolver=letsencrypt')
        if $DASH_AUTH_ENABLED; then DASH_LABELS+=(--label 'traefik.http.routers.traefik.middlewares=traefik-auth@docker'); fi
        ;;
      subdomain)
        if [[ -z "$DASHBOARD_HOST" ]]; then
          echo "::error::DASHBOARD_PUBLISH_MODES includes 'subdomain' but DASHBOARD_HOST is empty." >&2
          exit 1
        fi
        DASH_LABELS+=(--label 'traefik.enable=true')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.entrypoints=websecure')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.rule=Host("'"$DASHBOARD_HOST"'") && PathPrefix("/")')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.service=api@internal')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.tls=true')
        DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.tls.certresolver=letsencrypt')
        if $DASH_AUTH_ENABLED; then DASH_LABELS+=(--label 'traefik.http.routers.traefik-secure.middlewares=traefik-auth@docker'); fi
        ;;
    esac
  done

  # Append any accumulated labels
  if [[ ${#DASH_LABELS[@]} -gt 0 ]]; then
    RUN_ARGS+=("${DASH_LABELS[@]}")
  fi
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

if ! out=$("${RUN_ARGS[@]}" docker.io/traefik:"${TRAEFIK_VERSION}" 2>&1); then
  if printf '%s' "$out" | grep -qi 'already in use'; then
    echo "::warning::Name in use race detected; forcing cleanup and retry."
    cleanup_existing_traefik
    sleep 1
    if ! out2=$("${RUN_ARGS[@]}" docker.io/traefik:"${TRAEFIK_VERSION}" 2>&1); then
      echo "Failed to start Traefik container" >&2
      printf '%s\n' "$out2" >&2 || true
      podman logs traefik 2>&1 || true
      exit 1
    fi
  elif printf '%s' "$out" | grep -qi 'rootlessport .* privileged port'; then
    # Rootless publishing to ports 80/443 is still blocked even after sysctl/setcap attempts.
    # To avoid Traefik/app network mismatches, only allow host-network fallback when explicitly requested.
    if [ "$TRAEFIK_USE_HOST_NETWORK" != "true" ]; then
      echo "::error::Rootless publish to 80/443 failed and use_host_network=false. Refusing host-network fallback to avoid Traefik not seeing app containers on traefik-network."
      echo "Hint: Either (a) enable low-port binding for rootless podman (sysctl net.ipv4.ip_unprivileged_port_start=80), or (b) set use_host_network=true explicitly in setup-traefik inputs (apps would also need to run on host)."
      exit 1
    fi
    if [ "$SUDO_AVAILABLE" = "yes" ]; then
      echo "::notice::Rootless publish to 80/443 failed; attempting rootful fallback via sudo podman (host network) because use_host_network=true."
      ROOT_SOCK="/var/run/podman/podman.sock"
      # Build minimal rootful run args using host networking to avoid user-network mismatch
      RUN_ARGS_ROOT=(
        sudo podman run -d
        --name traefik
        --restart unless-stopped
      )
      # Prefer --replace if supported by rootful podman
      if sudo podman run --help 2>&1 | grep -q -- '--replace'; then
        RUN_ARGS_ROOT+=(--replace)
      fi
      RUN_ARGS_ROOT+=(--network host)
      # Mount same config and ACME storage from user scope; readable by root
      RUN_ARGS_ROOT+=(-v "$HOME/.config/traefik/traefik.yml":/etc/traefik/traefik.yml:ro)
      RUN_ARGS_ROOT+=(-v "$HOME/.local/share/traefik/acme.json":/letsencrypt/acme.json:Z)
      RUN_ARGS_ROOT+=(-v "$ROOT_SOCK":/var/run/docker.sock:Z)
      if $DASH_AUTH_ENABLED && [[ -n "$DASH_USERS_LOCAL_FILE" ]]; then
        RUN_ARGS_ROOT+=(-v "${DASH_USERS_LOCAL_FILE}:/etc/traefik/dashboard-users:Z")
      fi
      RUN_ARGS_ROOT+=(-e TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80)
      RUN_ARGS_ROOT+=(-e TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443)
      RUN_ARGS_ROOT+=(--label org.uactions.managed-by=uactions --label "org.uactions.traefik.confighash=${CONFIG_HASH}")
      if [[ "$TRAEFIK_ENABLE_ACME" == "true" ]]; then
        RUN_ARGS_ROOT+=(
          -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure
          -e TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https
          -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL="$TRAEFIK_EMAIL"
          -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/letsencrypt/acme.json
          -e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE_ENTRYPOINT=web
          -e TRAEFIK_ENTRYPOINTS_WEBSECURE_HTTP_TLS_CERTRESOLVER=letsencrypt
        )
        if [[ -n "$TRAEFIK_ACME_DNS_PROVIDER" ]]; then
          RUN_ARGS_ROOT+=(-e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER="$TRAEFIK_ACME_DNS_PROVIDER")
          if [[ -n "$TRAEFIK_ACME_DNS_RESOLVERS" ]]; then
            RUN_ARGS_ROOT+=(-e TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS="${TRAEFIK_ACME_DNS_RESOLVERS//,/\,}")
          fi
        fi
      fi
      if [[ "$TRAEFIK_PING_ENABLED" == "true" ]]; then
        RUN_ARGS_ROOT+=(-e TRAEFIK_PING=true -e TRAEFIK_PING_ENTRYPOINT=web)
      fi
      if [[ "$TRAEFIK_DNS_SERVERS" == "true" ]]; then
        IFS=', ' read -r -a _DNS_ARR <<< "$TRAEFIK_DNS_SERVERS"
        for _dns in "${_DNS_ARR[@]}"; do
          [[ -n "$_dns" ]] && RUN_ARGS_ROOT+=(--dns "$_dns")
        done
      fi
      # Attempt rootful start
      if ! out_root=$("${RUN_ARGS_ROOT[@]}" docker.io/traefik:"${TRAEFIK_VERSION}" 2>&1); then
        echo "Failed to start rootful Traefik container" >&2
        printf '%s\n' "$out_root" >&2 || true
        sudo podman logs traefik 2>&1 || true
        exit 1
      fi
      # Quick listener check; then exit early, skipping user-level systemd persistence
      echo "⏳ Waiting for Traefik listeners on ports 80/443 (rootful) ..."
      ok=false
      for i in {1..10}; do
        if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$' && \
           ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then
          ok=true; break
        fi
        sleep 2
      done
      if ! $ok; then
        echo "::error::Rootful Traefik did not open ports 80/443 after start." >&2
        sudo podman logs --tail=120 traefik 2>/dev/null || true
        exit 1
      fi
      echo "✅ Traefik container started (rootful fallback). Persistence via user systemd is skipped."
      exit 0
    fi
    echo "Failed to start Traefik container" >&2
    printf '%s\n' "$out" >&2 || true
    podman logs traefik 2>&1 || true
    exit 1
  else
    echo "Failed to start Traefik container" >&2
    printf '%s\n' "$out" >&2 || true
    podman logs traefik 2>&1 || true
    exit 1
  fi
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

ensure_traefik_systemd_user_service
