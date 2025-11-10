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


# --- Environment Setup ---------------------------------------------------------------
echo "🔧 Setting up deployment environment..."
echo "================================================================"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "👤 Remote user: ${CURRENT_USER} (uid:${CURRENT_UID})"
  echo "👥 Groups: ${CURRENT_GROUPS}"
  echo "🔑 Sudo: ${SUDO_STATUS}"
fi

# --- Execute Deployment ---------------------------------------------------------------
echo "🚀 Executing Setup Environmental Variable Script..."
echo "================================================================"
echo "  Script: $HOME/uactions/scripts/app/setup-env-file.sh"
echo "  App: $APP_SLUG"
echo "================================================================"

# --- Export Deployment Variables -----------------------------------------------------
echo "📤 Exporting deployment variables..."
echo "================================================================"

# Export environment variables for scripts
export REMOTE_ENV_FILE="$ENV_FILE"
export REMOTE_ENV_DIR="$ENV_DIR"

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
echo "================================================================"


# --- Execute Deployment ---------------------------------------------------------------
echo "🚀 Executing deployment script..."
echo "================================================================"
echo "  Script: $HOME/uactions/scripts/app/deploy-container.sh"
echo "  App: $APP_SLUG"
echo "  Image: $IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  Traefik: $TRAEFIK_ENABLED"
echo "  Sudo available: $SUDO_STATUS"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "📄 Using env file: $REMOTE_ENV_FILE"
fi
echo "================================================================"

"$HOME/uactions/scripts/app/deploy-container.sh"

echo "✅ Deployment completed successfully"
