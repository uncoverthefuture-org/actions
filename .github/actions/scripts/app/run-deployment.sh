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

# --- Traefik & domain routing ------------------------------------------------------
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-false}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-}"
DOMAIN_INPUT="${DOMAIN_INPUT:-}"
DOMAIN_DEFAULT="${DOMAIN_DEFAULT:-}"
ROUTER_NAME="${ROUTER_NAME:-}"

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
    echo '  sudo apt-get update -y' >&2
    echo '  sudo apt-get install -y podman curl jq ca-certificates' >&2
    echo 'Or re-run this action with a user that can install packages non-interactively.' >&2
    exit 1
  else
    echo "   Running (sudo apt-get update -y)"
    if sudo apt-get update -y; then
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
if [ -z "$UFW_PORTS" ]; then
  SSH_PORT_EFF="${SSH_PORT:-22}"
  UFW_PORTS="$SSH_PORT_EFF"
  if [ "${TRAEFIK_ENABLED:-false}" = "true" ]; then
    UFW_PORTS="$UFW_PORTS 80 443"
  else
    if [ -n "${HOST_PORT_IN:-}" ]; then
      UFW_PORTS="$UFW_PORTS ${HOST_PORT_IN}"
    fi
  fi
  if [ "${INSTALL_WEBMIN:-false}" = "true" ]; then
    UFW_PORTS="$UFW_PORTS 10000"
  fi
  if [ "${INSTALL_USERMIN:-false}" = "true" ]; then
    UFW_PORTS="$UFW_PORTS 20000"
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
if [ "${TRAEFIK_ENABLED:-false}" = "true" ]; then
  echo "================================================================"
  echo "🧪 Ensuring Traefik is ready ..."
  echo "================================================================"
  if [ -x "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh" ]; then
    export ENSURE_TRAEFIK="${ENSURE_TRAEFIK:-true}"
    "$HOME/uactions/scripts/traefik/ensure-traefik-ready.sh"
  else
    echo "::warning::ensure-traefik-ready.sh not found; skipping Traefik ensure step"
  fi
fi

echo "🚀 Executing deployment script..."
echo "================================================================"
echo "  Script: $HOME/uactions/scripts/app/deploy-container.sh"
echo "  App: $APP_SLUG"
echo "  Image: $IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  Traefik: $TRAEFIK_ENABLED"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "📄 Using env file: $REMOTE_ENV_FILE"
fi
echo "================================================================"

"$HOME/uactions/scripts/app/deploy-container.sh"

echo "✅ Deployment completed successfully"
