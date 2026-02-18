#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# run-deployment.sh - Deployment runner script for container deployments
# ----------------------------------------------------------------------------
# Purpose:
#   Handles environment setup, script staging, and execution for deployments.
#   Replaces long inline scripts in GitHub Actions with a clean, reusable script.
#
# Inputs (environment variables):
#   IMAGE_REGISTRY          - Container registry (e.g., ghcr.io)
#   IMAGE_NAME              - Container image name
#   IMAGE_TAG               - Container image tag
#   REGISTRY_LOGIN          - Whether to login to registry (true/false)
#   REGISTRY_USERNAME       - Registry username (if needed)
#   REGISTRY_TOKEN          - Registry token/password (if needed)
#   APP_SLUG                - Application slug
#   ENV_NAME                - Environment name (production/staging/etc.)
#   CONTAINER_NAME_IN       - Custom container name (optional)
#   ENV_FILE_PATH_BASE      - Base path for env files (default: /var/deployments)
#   HOST_PORT_IN            - Host port mapping (optional)
#   CONTAINER_PORT_IN       - Container port (default: 3000)
#   EXTRA_RUN_ARGS          - Extra podman run arguments
#   RESTART_POLICY          - Container restart policy (default: unless-stopped)
#   MEMORY_LIMIT            - Container memory limit (default: 512m)
#   TRAEFIK_ENABLED         - Enable Traefik routing (true/false)
#   DOMAIN_INPUT            - Custom domain (optional)
#   DOMAIN_DEFAULT          - Default domain for Traefik
#   ROUTER_NAME             - Traefik router name
#   GITHUB_REF_NAME         - GitHub ref name for env detection
#   GITHUB_REPOSITORY       - GitHub repository for app slug derivation
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail



SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Logging bootstrap: source shared helper so all scripts emit consistent
# diagnostics. RUN_SCRIPT_NAME labels log entries for easier aggregation.
RUN_SCRIPT_NAME="run-deployment.sh"
# shellcheck source=../log/logging.sh
source "${SCRIPT_DIR}/../log/logging.sh"
# shellcheck source=../util/normalize.sh
source "${SCRIPT_DIR}/../util/normalize.sh"
# shellcheck source=../util/sudo.sh
source "${SCRIPT_DIR}/../util/sudo.sh"

if [ "${DEBUG:-false}" = "true" ]; then set -x; fi

# --- Resolve inputs -----------------------------------------------------------------
# Get all environment variables with defaults
# --- Image & registry inputs --------------------------------------------------------
IMAGE_REGISTRY_RAW="${IMAGE_REGISTRY:-}"
IMAGE_REGISTRY=$(normalize_string "$IMAGE_REGISTRY_RAW" "image registry")
IMAGE_NAME_RAW="${IMAGE_NAME:-}"
IMAGE_NAME=$(normalize_string "$IMAGE_NAME_RAW" "image name")
IMAGE_TAG="${IMAGE_TAG:-}"

# --- Registry authentication --------------------------------------------------------
REGISTRY_LOGIN="${REGISTRY_LOGIN:-false}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"

# --- Application & environment metadata --------------------------------------------
APP_SLUG_RAW="${APP_SLUG:-}"
APP_SLUG=$(normalize_string "$APP_SLUG_RAW" "app slug")
ENV_NAME_RAW="${ENV_NAME:-}"
ENV_NAME=$(normalize_string "$ENV_NAME_RAW" "env name")
REF_NAME="${GITHUB_REF_NAME:-}"
ENV_B64="${ENV_B64:-}"
ENV_CONTENT="${ENV_CONTENT:-}"
REPO_NAME_RAW="${GITHUB_REPOSITORY:-}"
CONTAINER_NAME_IN="${CONTAINER_NAME_IN:-}"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-${HOME}/deployments}"

# --- Runtime configuration ---------------------------------------------------------
HOST_PORT_IN="${HOST_PORT_IN:-}"
CONTAINER_PORT_IN="${CONTAINER_PORT_IN:-8080}"
EXTRA_RUN_ARGS="${EXTRA_RUN_ARGS:-}"
RESTART_POLICY="${RESTART_POLICY:-unless-stopped}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
CPU_LIMIT="${CPU_LIMIT:-0.5}"
PORTAINER_HTTPS_PORT="${PORTAINER_HTTPS_PORT:-9443}"
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"

# --- Traefik & domain routing ------------------------------------------------------
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-false}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-}"
DOMAIN_INPUT="${DOMAIN_INPUT:-}"
DOMAIN_DEFAULT="${DOMAIN_DEFAULT:-}"
ROUTER_NAME="${ROUTER_NAME:-}"

# When PORTAINER_DOMAIN is not explicitly provided but an app domain exists,
# derive a friendly default of the form portainer.<apex>. Example:
#   DOMAIN_DEFAULT=dev.shakohub.com  →  PORTAINER_DOMAIN=portainer.shakohub.com
# This keeps Portainer tied to the main site domain while remaining
# environment-agnostic. Callers can still override PORTAINER_DOMAIN when they
# need a different host.
if [ -z "$PORTAINER_DOMAIN" ]; then
  EFFECTIVE_DOMAIN_FOR_PORTAINER="${DOMAIN_INPUT:-${DOMAIN_DEFAULT:-}}"
  if [ -n "$EFFECTIVE_DOMAIN_FOR_PORTAINER" ]; then
    dom_lower=$(printf '%s' "$EFFECTIVE_DOMAIN_FOR_PORTAINER" | tr '[:upper:]' '[:lower:]')
    # Strip any leading www. before computing the apex.
    dom_stripped="${dom_lower#www.}"
    IFS='.' read -r -a parts <<<"$dom_stripped"; count=${#parts[@]}
    if (( count >= 2 )); then
      apex="${parts[count-2]}.${parts[count-1]}"
    else
      apex="$dom_stripped"
    fi
    PORTAINER_DOMAIN="portainer.${apex}"
  fi
fi

# --- User context ------------------------------------------------------
CURRENT_USER="${CURRENT_USER:-$(id -un)}"
CURRENT_UID="${CURRENT_UID:-$(id -u)}"
CURRENT_GROUPS="${CURRENT_GROUPS:-$(id -Gn)}"

# Determine whether passwordless sudo is available using shared helper.
# Example:
#   SUDO_STATUS="$(detect_sudo_status "yes" "no")"
SUDO_STATUS="$(detect_sudo_status)"

echo "================================================================"
echo "📛 Confirming podman installation..."
echo "================================================================"
if command -v podman >/dev/null 2>&1; then
  echo "✅ Podman is already installed"
  echo "   Podman version: $(podman --version)"
  echo "   Podman info: $(podman info 2>/dev/null | head -n 5)"
else
  echo "❌ Podman is not installed on this host."
  echo "   This deployment requires Podman to be installed on the remote host."
  if [[ "${SUDO_STATUS:-available}" == "unavailable" ]]; then
    echo "Detected: user=$(id -un); sudo(non-interactive)=${SUDO_STATUS}" >&2
    echo 'Install manually as root then re-run:' >&2
    echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
    echo '  sudo apt-get install -y podman curl jq ca-certificates' >&2
    echo 'Or re-run this action with a user that can install packages non-interactively.' >&2
    exit 1
  else
    # Use --allow-releaseinfo-change so noninteractive runs do not fail when a
    # trusted repository (for example, the ondrej/php PPA) updates its
    # metadata fields such as Label/Suite/codename.
    echo "   Running (sudo apt-get update -y --allow-releaseinfo-change)"
    if sudo apt-get update -y --allow-releaseinfo-change; then
      echo "   ✅ apt-get update completed"
    else
      echo "::error::apt-get update failed" >&2
      exit 1
    fi

    echo "   Running (sudo apt-get install -y podman curl jq ca-certificates)"
    if sudo apt-get install -y podman curl jq ca-certificates; then
      echo "   ✅ Podman and dependencies installed"
    else
      echo "::error::apt-get install podman curl jq ca-certificates failed" >&2
      exit 1
    fi
  fi
fi

# --- Install Portainer (after Traefik ensure) ---------------------------------------
if [ "${INSTALL_PORTAINER:-false}" = "true" ]; then
  echo "================================================================"
  echo "🛠 Installing Portainer (as requested) ..."
  echo "================================================================"
  if [ -x "$HOME/uactions/scripts/infra/install-portainer.sh" ]; then
    # Pass through admin auto-init controls so install-portainer.sh can
    # bootstrap the initial Portainer admin user via the HTTPS API on first
    # install. Example: PORTAINER_ADMIN_AUTO_INIT=true with an explicit
    # PORTAINER_ADMIN_PASSWORD or the default 12345678 when no password is
    # provided (see ssh-container-deploy README for overrides).
    INSTALL_PORTAINER="${INSTALL_PORTAINER:-true}" \
      PORTAINER_HTTPS_PORT="${PORTAINER_HTTPS_PORT:-9443}" \
      TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-traefik-network}" \
      PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}" \
      PORTAINER_ADMIN_AUTO_INIT="${PORTAINER_ADMIN_AUTO_INIT:-true}" \
      PORTAINER_ADMIN_USERNAME="${PORTAINER_ADMIN_USERNAME:-admin}" \
      PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-}" \
      "$HOME/uactions/scripts/infra/install-portainer.sh"
  else
    echo "::warning::install-portainer.sh not found; skipping Portainer installation"
  fi
fi


# --- Environment Setup ---------------------------------------------------------------
echo "🔧 Setting up deployment environment..."
echo "================================================================"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "👤 Remote user: ${CURRENT_USER} (uid:${CURRENT_UID})"
  echo "👥 Groups: ${CURRENT_GROUPS}"
  echo "🔑 Sudo: ${SUDO_STATUS}"
fi

# --- Execute Deployment ---------------------------------------------------------------
echo "================================================================"
echo "🚀 Executing Setup Environmental Variable Script..."
echo "================================================================"
echo "  Script: $HOME/uactions/scripts/app/setup-env-file.sh"
echo "  App: $APP_SLUG"

# Source the setup script so its exported variables persist in this shell
if [ -f "$HOME/uactions/scripts/app/setup-env-file.sh" ]; then
  # shellcheck source=app/setup-env-file.sh
  . "$HOME/uactions/scripts/app/setup-env-file.sh"
else
  echo "::error::setup-env-file.sh not found on remote host" >&2
  exit 1
fi

# --- Verify Environment File (Strict Update Check) -----------------------------------
echo "================================================================"
echo "🔍 Verifying environment file update..."
echo "================================================================"
if [ -f "$HOME/uactions/scripts/app/verify-env-file.sh" ]; then
  # Pass the original inputs to verification script
  export ENV_FILE_PATH="$HOME/uactions/scripts/app/verify-env-file.sh"
  # Use the same ENV_B64 / ENV_CONTENT variables as setup-env-file.sh used
  
  # Note: setup-env-file.sh exports REMOTE_ENV_FILE which points to the actual file
  CHECK_FILE="${REMOTE_ENV_FILE:-$ENV_FILE}"
  
  if ENV_FILE_PATH="$CHECK_FILE" ENV_B64="${ENV_B64:-}" ENV_CONTENT="${ENV_CONTENT:-}" "$HOME/uactions/scripts/app/verify-env-file.sh"; then
    echo "  ✓ Verification successful"
  else
    echo "::error::Environment file verification failed! Aborting deployment." >&2
    exit 1
  fi
else
  echo "::warning::verify-env-file.sh not found; skipping strict verification"
fi

# --- Export Deployment Variables -----------------------------------------------------
echo "================================================================"
echo "📤 Exporting deployment variables..."
echo "================================================================"

# Export environment variables for scripts using values created by setup-env-file.sh
export REMOTE_ENV_DIR="${REMOTE_ENV_DIR:-$ENV_DIR}"
export REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-$ENV_FILE}"

# Registry settings
export IMAGE_REGISTRY
export IMAGE_NAME
export IMAGE_TAG
export REGISTRY_LOGIN

# Set registry credentials based on registry type
if [ "$IMAGE_REGISTRY" = 'ghcr.io' ]; then
  export REGISTRY_USERNAME="${REGISTRY_USERNAME:-$GITHUB_ACTOR}"
  export REGISTRY_TOKEN="${REGISTRY_TOKEN:-$GITHUB_TOKEN}"
else
  export REGISTRY_USERNAME
  export REGISTRY_TOKEN
fi

# Application settings
export APP_SLUG
export ENV_NAME
export CONTAINER_NAME_IN
export ENV_FILE_PATH_BASE

# Port settings
export HOST_PORT_IN
export CONTAINER_PORT_IN

# Container settings
export EXTRA_RUN_ARGS
export RESTART_POLICY
export MEMORY_LIMIT
export CPU_LIMIT

# Environment file mount settings (for frameworks like Laravel)
export ENV_FILE_MOUNT_ENABLED
export ENV_FILE_CONTAINER_PATH

# Traefik settings
export TRAEFIK_ENABLED
export DOMAIN_INPUT
export DOMAIN_DEFAULT
export ROUTER_NAME
export TRAEFIK_ENABLE_ACME
export TRAEFIK_NETWORK_NAME
# Domain aliases for Traefik Host() rule (optional)
export DOMAIN_ALIASES
export INCLUDE_WWW_ALIAS
export SUDO_STATUS
# Additional Traefik setup variables (export if present in environment)
export TRAEFIK_EMAIL
export TRAEFIK_VERSION
export TRAEFIK_PING_ENABLED
export TRAEFIK_DASHBOARD
export DASHBOARD_PUBLISH_MODES
export DASHBOARD_HOST
export DASHBOARD_USER
export DASHBOARD_PASS_BCRYPT
export DASHBOARD_PASSWORD
export DASHBOARD_USERS_B64
export TRAEFIK_USE_HOST_NETWORK
export TRAEFIK_ENABLE_METRICS
export TRAEFIK_METRICS_ENTRYPOINT
export TRAEFIK_METRICS_ADDRESS
export TRAEFIK_ACME_DNS_PROVIDER
export TRAEFIK_ACME_DNS_RESOLVERS
export TRAEFIK_DNS_SERVERS
echo "================================================================"


# --- Execute Deployment ---------------------------------------------------------------
echo "🔒 Configuring firewall (UFW) ..."
echo "================================================================"
UFW_PORTS_INPUT="${UFW_ALLOW_PORTS_INPUT:-}"
UFW_PORTS="$UFW_PORTS_INPUT"

# Safeguard: Ensure core ports are present even if UFW_ALLOW_PORTS_INPUT is custom
# This prevents accidental lockout or service isolation when using Traefik.
SSH_PORT_EFF="${SSH_PORT:-22}"
if [[ ! " $UFW_PORTS " =~ [[:space:]]${SSH_PORT_EFF}([[:space:]]|$) ]]; then
  UFW_PORTS="${UFW_PORTS:+$UFW_PORTS }$SSH_PORT_EFF"
fi

if [ "${TRAEFIK_ENABLED:-false}" = "true" ]; then
  for p in 80 443; do
    if [[ ! " $UFW_PORTS " =~ [[:space:]]${p}([[:space:]]|$) ]]; then
      UFW_PORTS="$UFW_PORTS $p"
    fi
  done
fi

if [ -z "$UFW_PORTS_INPUT" ]; then
  # If the user didn't provide custom ports, add management tool defaults
  if [ "${INSTALL_WEBMIN:-false}" = "true" ] && [[ ! " $UFW_PORTS " =~ [[:space:]]10000([[:space:]]|$) ]]; then
    UFW_PORTS="$UFW_PORTS 10000"
  fi
  if [ "${INSTALL_USERMIN:-false}" = "true" ] && [[ ! " $UFW_PORTS " =~ [[:space:]]20000([[:space:]]|$) ]]; then
    UFW_PORTS="$UFW_PORTS 20000"
  fi
  if [ "${INSTALL_PORTAINER:-false}" = "true" ] && [[ ! " $UFW_PORTS " =~ [[:space:]]${PORTAINER_HTTPS_PORT:-9443}([[:space:]]|$) ]]; then
    UFW_PORTS="$UFW_PORTS ${PORTAINER_HTTPS_PORT:-9443}"
  fi
fi

if [ -x "$HOME/uactions/scripts/infra/configure-ufw.sh" ]; then
  export SSH_PORT
  export UFW_ALLOW_PORTS="$UFW_PORTS"
  export ENABLE_PODMAN_FORWARD="${TRAEFIK_ENABLED:-false}"
  export ROUTE_PORTS='80 443'
  export SET_FORWARD_POLICY_ACCEPT='true'
  export WAN_IFACE=''
  export PODMAN_IFACE=''
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo env \
      SSH_PORT="$SSH_PORT" \
      UFW_ALLOW_PORTS="$UFW_ALLOW_PORTS" \
      ENABLE_PODMAN_FORWARD="$ENABLE_PODMAN_FORWARD" \
      ROUTE_PORTS="$ROUTE_PORTS" \
      SET_FORWARD_POLICY_ACCEPT="$SET_FORWARD_POLICY_ACCEPT" \
      WAN_IFACE="$WAN_IFACE" \
      PODMAN_IFACE="$PODMAN_IFACE" \
      "$HOME/uactions/scripts/infra/configure-ufw.sh"
  else
    "$HOME/uactions/scripts/infra/configure-ufw.sh"
  fi
else
  echo "::warning::configure-ufw.sh not found; skipping firewall configuration"
fi

# --- Optional management tools (Webmin/Usermin) ------------------------------------
if [ "${INSTALL_WEBMIN:-false}" = "true" ] || [ "${INSTALL_USERMIN:-false}" = "true" ]; then
  echo "================================================================"
  echo "🛠 Installing Webmin/Usermin (as requested) ..."
  echo "================================================================"
  if [ -x "$HOME/uactions/scripts/infra/install-webmin.sh" ]; then
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo env INSTALL_WEBMIN="${INSTALL_WEBMIN:-false}" INSTALL_USERMIN="${INSTALL_USERMIN:-false}" "$HOME/uactions/scripts/infra/install-webmin.sh"
    else
      "$HOME/uactions/scripts/infra/install-webmin.sh"
    fi
  else
    echo "::warning::install-webmin.sh not found; skipping Webmin/Usermin installation"
  fi
fi

# --- Ensure Traefik is ready (idempotent) -------------------------------------------
# TRAEFIK_MODE can be passed in by callers, but when unset we infer a sensible
# default so that container-managed Traefik and Quadlet-managed Traefik both
# converge through the same entrypoint.
#
# IMPORTANT: Quadlet support requires Podman >= 4.4. Older versions (e.g., 3.4.4
# on Ubuntu 22.04) may have leftover Quadlet files from failed deployments, but
# the Quadlet generators don't work properly. We MUST check the Podman version
# before using Quadlet mode based on file presence.

# Helper: Check if Podman version supports Quadlet (>= 4.4)
# Returns 0 (true) if supported, 1 (false) otherwise
podman_supports_quadlet() {
  local podman_ver=""
  if command -v podman >/dev/null 2>&1; then
    podman_ver=$(podman --version 2>/dev/null | awk '{print $3}' | cut -d'-' -f1 || echo "")
  fi
  if [ -z "$podman_ver" ]; then
    return 1  # Unknown version, assume no Quadlet support
  fi
  local podman_major="${podman_ver%%.*}"
  local podman_minor_patch="${podman_ver#*.}"
  local podman_minor="${podman_minor_patch%%.*}"
  if { [ "$podman_major" -gt 4 ] || { [ "$podman_major" -eq 4 ] && [ "$podman_minor" -ge 4 ]; }; }; then
    return 0  # Podman >= 4.4 supports Quadlet
  fi
  return 1  # Podman < 4.4 does not support Quadlet
}

# Helper: Clean up stale Quadlet files that conflict with container-managed Traefik
# This is necessary when:
#   - Server has old Podman (< 4.4) that doesn't support Quadlet properly
#   - Previous deployment attempts left Quadlet socket/unit files
#   - These files cause "Socket service traefik.service not loaded, refusing" errors
cleanup_stale_quadlet_traefik() {
  local cleaned=false
  echo "🧹 Cleaning up stale Quadlet Traefik files (container mode on Podman < 4.4)..."

  # Stop and disable user-level socket units if they exist
  if command -v systemctl >/dev/null 2>&1; then
    for unit in http.socket https.socket traefik.service container-traefik.service; do
      if systemctl --user is-enabled "$unit" >/dev/null 2>&1 || \
         systemctl --user is-active "$unit" >/dev/null 2>&1; then
        systemctl --user stop "$unit" >/dev/null 2>&1 || true
        systemctl --user disable "$unit" >/dev/null 2>&1 || true
        echo "  ✓ Stopped/disabled $unit"
        cleaned=true
      fi
    done
  fi

  # Remove socket unit files
  for f in "$HOME/.config/systemd/user/http.socket" \
           "$HOME/.config/systemd/user/https.socket"; do
    if [ -f "$f" ]; then
      rm -f "$f"
      echo "  ✓ Removed $f"
      cleaned=true
    fi
  done

  # Remove Quadlet container unit files for Traefik
  for f in "$HOME/.config/containers/systemd/traefik.container" \
           "$HOME/.config/containers/systemd/traefik-network.network"; do
    if [ -f "$f" ]; then
      rm -f "$f"
      echo "  ✓ Removed $f"
      cleaned=true
    fi
  done

  # Reload systemd user daemon to pick up removals
  if $cleaned && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    echo "  ✓ Reloaded systemd --user daemon"
  fi

  if ! $cleaned; then
    echo "  ✓ No stale Quadlet files found"
  fi
}

TRAEFIK_MODE="${TRAEFIK_MODE:-}"
if [ -z "$TRAEFIK_MODE" ]; then
  # Check Podman version FIRST before inferring mode from file presence.
  # This prevents stale Quadlet files from triggering Quadlet mode on old Podman.
  if podman_supports_quadlet; then
    # Podman >= 4.4: safe to use Quadlet if files exist
    if [ -f "$HOME/.config/containers/systemd/traefik.container" ] || \
       [ -f "$HOME/.config/systemd/user/http.socket" ] || \
       [ -f "$HOME/.config/systemd/user/https.socket" ]; then
      TRAEFIK_MODE="quadlet"
      echo "::notice::Podman supports Quadlet and Quadlet files found; using TRAEFIK_MODE=quadlet"
    else
      TRAEFIK_MODE="container"
      echo "::notice::Podman supports Quadlet but no Quadlet files found; using TRAEFIK_MODE=container"
    fi
  else
    # Podman < 4.4: MUST use container mode, clean up any stale Quadlet files
    TRAEFIK_MODE="container"
    _has_stale_files=false
    if [ -f "$HOME/.config/containers/systemd/traefik.container" ] || \
       [ -f "$HOME/.config/systemd/user/http.socket" ] || \
       [ -f "$HOME/.config/systemd/user/https.socket" ]; then
      _has_stale_files=true
    fi
    if $_has_stale_files; then
      echo "::warning::Podman does not support Quadlet (< 4.4) but stale Quadlet files exist; cleaning up..."
      cleanup_stale_quadlet_traefik
    else
      echo "::notice::Podman does not support Quadlet (< 4.4); using TRAEFIK_MODE=container"
    fi
  fi
else
  # TRAEFIK_MODE was explicitly set by caller (e.g., from action.yml)
  # If set to 'container' and we have stale Quadlet files, clean them up
  if [ "$TRAEFIK_MODE" = "container" ]; then
    if [ -f "$HOME/.config/systemd/user/http.socket" ] || \
       [ -f "$HOME/.config/systemd/user/https.socket" ]; then
      echo "::notice::TRAEFIK_MODE=container (explicit) but stale socket files exist; cleaning up..."
      cleanup_stale_quadlet_traefik
    fi
  fi
  echo "::notice::Using caller-provided TRAEFIK_MODE=$TRAEFIK_MODE"
fi

if [ "${TRAEFIK_ENABLED:-false}" = "true" ]; then
  echo "================================================================"
  echo "🧪 Ensuring Traefik is ready ..."
  echo "================================================================"
  if [ "$TRAEFIK_MODE" = "quadlet" ]; then
    # When Traefik is managed via Quadlet/socket activation, the
    # ensure-traefik-ready.sh script will reconcile Quadlet units via
    # install-quadlet-sockets.sh instead of recreating a standalone
    # container. We still rely on the same preflight/health checks.
    if [ -x "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh" ]; then
      export ENSURE_TRAEFIK="${ENSURE_TRAEFIK:-true}"
      export TRAEFIK_MODE
      "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh"
    else
      echo "::warning::ensure-traefik-ready.sh not found; skipping Traefik ensure step (Quadlet mode)"
    fi
  else
    if [ -x "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh" ]; then
      export ENSURE_TRAEFIK="${ENSURE_TRAEFIK:-true}"
      export TRAEFIK_MODE
      "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh"
    else
      echo "::warning::ensure-traefik-ready.sh not found; skipping Traefik ensure step"
    fi
  fi
fi

echo "🚀 Executing deployment script..."
echo "================================================================"
echo "  Script: $HOME/uactions/scripts/app/deploy-container.sh"
echo "  App: $APP_SLUG"
echo "  Image: $IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  Traefik: $TRAEFIK_ENABLED"
echo "  Env Directory: ${REMOTE_ENV_DIR:-'(not set)'}"
echo "  Env File: ${REMOTE_ENV_FILE:-'(not set)'}"

# Verify environment is properly set up before deployment
if [ -n "$REMOTE_ENV_FILE" ]; then
  if [ -f "$REMOTE_ENV_FILE" ]; then
    echo "  ✓ Environment file exists"
    if [ "${DEBUG:-false}" = "true" ]; then
      echo "  • File size: $(stat -c%s "$REMOTE_ENV_FILE" 2>/dev/null || stat -f%z "$REMOTE_ENV_FILE" 2>/dev/null || echo 'unknown') bytes"
      echo "  • Last modified: $(stat -c%y "$REMOTE_ENV_FILE" 2>/dev/null || stat -f%Sm "$REMOTE_ENV_FILE" 2>/dev/null || echo 'unknown')"
    fi
  else
    echo "  ⚠ Environment file does not exist at: $REMOTE_ENV_FILE"
  fi
else
  echo "  ⚠ REMOTE_ENV_FILE is not set"
fi
echo "================================================================"

# Ensure all environment variables are exported for deploy-container.sh
export APP_SLUG
export ENV_NAME
export IMAGE_REGISTRY
export IMAGE_NAME
export IMAGE_TAG
export REMOTE_ENV_DIR
export REMOTE_ENV_FILE
export ENV_FILE_PATH_BASE
export TRAEFIK_ENABLED
export TRAEFIK_NETWORK_NAME

"$HOME/uactions/scripts/app/deploy-container.sh"

# --- Podman storage cleanup (optional, enabled by default) ------------------------
# To prevent Podman overlay storage from growing without bound, run a safe, age-
# based prune after successful deployments. This only removes stopped containers
# and unused images, leaving running workloads intact. Callers can tune or
# disable via environment variables, for example:
#   PODMAN_PRUNE_ENABLED=false
#   PODMAN_PRUNE_MIN_AGE_DAYS=1 (default: 1 day for automatic cleanup)
#   PODMAN_PRUNE_KEEP_RECENT_IMAGES=5
#   PODMAN_PRUNE_AGGRESSIVE=true (default: true - removes ALL stopped containers immediately)
PODMAN_PRUNE_ENABLED="${PODMAN_PRUNE_ENABLED:-true}"
PODMAN_PRUNE_MIN_AGE_DAYS="${PODMAN_PRUNE_MIN_AGE_DAYS:-1}"
PODMAN_PRUNE_KEEP_RECENT_IMAGES="${PODMAN_PRUNE_KEEP_RECENT_IMAGES:-2}"
PODMAN_PRUNE_AGGRESSIVE="${PODMAN_PRUNE_AGGRESSIVE:-true}"

# Compute container name for preservation during pruning
CONTAINER_NAME_FOR_PRUNE="${CONTAINER_NAME_IN:-}"
if [ -z "$CONTAINER_NAME_FOR_PRUNE" ]; then
  CONTAINER_NAME_FOR_PRUNE="${APP_SLUG}-${ENV_NAME}"
fi

# Compute image ref for preservation during pruning
IMAGE_REF_FOR_PRUNE="${IMAGE_REGISTRY:+$IMAGE_REGISTRY/}${IMAGE_NAME}:${IMAGE_TAG}"

if [ "$PODMAN_PRUNE_ENABLED" = "true" ]; then
  if [ -f "$HOME/uactions/scripts/infra/prune-podman-storage.sh" ]; then
    echo "================================================================"
    echo "🧹 Running Podman storage cleanup"
    echo "   Mode: ${PODMAN_PRUNE_AGGRESSIVE:+AGGRESSIVE (remove all stopped containers immediately)}${PODMAN_PRUNE_AGGRESSIVE:-age-based (${PODMAN_PRUNE_MIN_AGE_DAYS} days)}"
    echo "   App: ${APP_SLUG}"
    echo "   Env: ${ENV_NAME}"
    echo "   Preserving: ${CONTAINER_NAME_FOR_PRUNE}"
    echo "================================================================"
    PODMAN_PRUNE_ENABLED="$PODMAN_PRUNE_ENABLED" \
      PODMAN_PRUNE_MIN_AGE_DAYS="$PODMAN_PRUNE_MIN_AGE_DAYS" \
      PODMAN_PRUNE_KEEP_RECENT_IMAGES="$PODMAN_PRUNE_KEEP_RECENT_IMAGES" \
      PODMAN_PRUNE_AGGRESSIVE="$PODMAN_PRUNE_AGGRESSIVE" \
      APP_SLUG="$APP_SLUG" \
      ENV_NAME="$ENV_NAME" \
      CONTAINER_NAME="$CONTAINER_NAME_FOR_PRUNE" \
      IMAGE_REF="$IMAGE_REF_FOR_PRUNE" \
      bash "$HOME/uactions/scripts/infra/prune-podman-storage.sh" || echo "::warning::prune-podman-storage.sh reported an error; continuing deployment"
  else
    echo "::notice::PODMAN_PRUNE_ENABLED=true but prune-podman-storage.sh not found; skipping Podman storage cleanup" >&2
  fi
fi

# --- Management interfaces summary -------------------------------------------------
# Surface best-effort access URLs for Portainer/Webmin/Usermin so operators can
# quickly reach management UIs after a successful deploy. For direct-port
# access, prefer the apex/base domain (for example, dev.example.com →
# example.com) when an env-specific subdomain is used, otherwise fall back to
# the primary host IP.
ACCESS_HOST=""
EFFECTIVE_DOMAIN="${DOMAIN_INPUT:-${DOMAIN_DEFAULT:-}}"
if [ -n "$EFFECTIVE_DOMAIN" ]; then
  # Count labels; when there are 3+ labels (for example dev.posteat.co.uk),
  # strip the first label so that direct-port URLs use the apex/base domain
  # (posteat.co.uk). For 2-label domains (example.com), keep the full domain.
  label_count=$(printf '%s' "$EFFECTIVE_DOMAIN" | awk -F'.' '{print NF}')
  if [ "$label_count" -ge 3 ]; then
    ACCESS_HOST="${EFFECTIVE_DOMAIN#*.}"
  else
    ACCESS_HOST="$EFFECTIVE_DOMAIN"
  fi
fi
if [ -z "$ACCESS_HOST" ]; then
  if command -v hostname >/dev/null 2>&1; then
    ACCESS_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
fi
if [ -z "$ACCESS_HOST" ]; then
  ACCESS_HOST="<server-ip-or-hostname>"
fi

echo "================================================================"
echo "🧭 Management interfaces (this host)"
echo "================================================================"
if [ "${INSTALL_PORTAINER:-false}" = "true" ]; then
  echo "Portainer UI (HTTPS): https://${ACCESS_HOST}:${PORTAINER_HTTPS_PORT:-9443}"
  # When PORTAINER_DOMAIN is configured (for example portainer.shakohub.com),
  # Traefik will also expose the UI via HTTPS on port 443 for that host. This
  # line helps operators discover the friendly URL without remembering the
  # direct :9443 port.
  if [ -n "${PORTAINER_DOMAIN:-}" ]; then
    echo "Portainer via Traefik: https://${PORTAINER_DOMAIN}"
  fi
fi
if [ "${INSTALL_WEBMIN:-false}" = "true" ]; then
  echo "Webmin (default HTTPS): https://${ACCESS_HOST}:10000"
fi
if [ "${INSTALL_USERMIN:-false}" = "true" ]; then
  echo "Usermin (default HTTPS): https://${ACCESS_HOST}:20000"
fi

echo "✅ Deployment completed successfully"
