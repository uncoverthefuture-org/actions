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

# --- Resolve inputs -----------------------------------------------------------------
# Get all environment variables with defaults
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
REGISTRY_LOGIN="${REGISTRY_LOGIN:-false}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"
APP_SLUG="${APP_SLUG:-}"
ENV_NAME="${ENV_NAME:-}"
CONTAINER_NAME_IN="${CONTAINER_NAME_IN:-}"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-/var/deployments}"
HOST_PORT_IN="${HOST_PORT_IN:-}"
CONTAINER_PORT_IN="${CONTAINER_PORT_IN:-3000}"
EXTRA_RUN_ARGS="${EXTRA_RUN_ARGS:-}"
RESTART_POLICY="${RESTART_POLICY:-unless-stopped}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-true}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-}"
DOMAIN_INPUT="${DOMAIN_INPUT:-}"
DOMAIN_DEFAULT="${DOMAIN_DEFAULT:-}"
ROUTER_NAME="${ROUTER_NAME:-}"

# --- Environment Setup ---------------------------------------------------------------
echo "🔧 Setting up deployment environment..."

CURRENT_USER="$(id -un)"
CURRENT_UID="$(id -u)"
CURRENT_GROUPS="$(id -Gn)"
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO_STATUS="available"
else
  SUDO_STATUS="not available"
fi
echo "👤 Remote user: ${CURRENT_USER} (uid:${CURRENT_UID})"
echo "👥 Groups: ${CURRENT_GROUPS}"
echo "🔑 sudo: ${SUDO_STATUS}"

# Determine environment name from GitHub ref if not provided
if [ -z "$ENV_NAME" ]; then
  REF_NAME="${GITHUB_REF_NAME:-}"
  case "$REF_NAME" in
    main|master|production) ENV_NAME='production' ;;
    stage|staging) ENV_NAME='staging' ;;
    dev|develop|development) ENV_NAME='development' ;;
    refs/tags/*) ENV_NAME='production' ;;
    *) ENV_NAME='development' ;;
  esac
fi

# Normalize 'dev' to 'development'
if [ "$ENV_NAME" = "dev" ]; then
  ENV_NAME='development'
fi

# Determine app slug from GitHub repository if not provided
if [ -z "$APP_SLUG" ]; then
  REPO_NAME_RAW="${GITHUB_REPOSITORY:-}"
  if [ -n "$REPO_NAME_RAW" ]; then
    REPO_NAME="${REPO_NAME_RAW##*/}"
  else
    REPO_NAME='app'
  fi
  APP_SLUG=$(printf '%s' "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
fi

# Setup environment directories and files
ENV_ROOT_DEFAULT="${HOME}/deployments"
ENV_ROOT="${ENV_FILE_PATH_BASE:-$ENV_ROOT_DEFAULT}"
ENV_DIR="${ENV_ROOT}/${ENV_NAME}/${APP_SLUG}"

echo "📁 Preparing environment directory: $ENV_DIR"
if [ -d "$ENV_DIR" ] && [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: choose a user-owned path (e.g., $HOME/deployments) or adjust permissions." >&2
  exit 1
fi
if [ ! -d "$ENV_DIR" ]; then
  if ! mkdir -p "$ENV_DIR"; then
    echo "::error::Unable to create env directory $ENV_DIR" >&2
    echo "Hint: ensure the SSH user owns the parent directory or use a user-writable location." >&2
    exit 1
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: run 'chown -R $CURRENT_USER $ENV_DIR' on the host or select a user-owned path." >&2
  exit 1
fi

ENV_FILE="${ENV_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "📄 Creating environment file: $ENV_FILE"
  {
    printf '# Generated by uactions package (run-deployment.sh).\n'
    printf '# Populate with KEY=VALUE pairs required for your deployment.\n'
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
else
  echo "📄 Environment file already exists: $ENV_FILE"
fi

# Source environment variables if file exists
if [ -f "$ENV_FILE" ]; then
  echo "🔄 Sourcing environment variables from $ENV_FILE"
  set -a
  . "$ENV_FILE"
  set +a
else
  echo "::warning::Environment file $ENV_FILE not found; continuing without sourcing"
fi

# Export environment variables for scripts
export REMOTE_ENV_FILE="$ENV_FILE"
export REMOTE_ENV_DIR="$ENV_DIR"

# --- Podman Helper -------------------------------------------------------------------
echo "🐳 Verifying podman availability..."

# Verify podman is available
if ! command -v podman >/dev/null 2>&1; then
  echo '::error::podman is not installed on the remote host'
  echo 'Error: podman is not installed on the remote host.' >&2
  echo 'Hint: enable host preparation in the calling action (prepare_host: true) or install podman manually.' >&2
  exit 1
fi

# --- Script Staging ------------------------------------------------------------------
echo "📦 Staging deployment scripts..."
cd /

# Ensure scripts directory exists
mkdir -p /opt/uactions/scripts/app

# Move uploaded deploy script if it exists
if [ -f /tmp/deploy-container.sh ]; then
  echo "📋 Moving deploy-container.sh to /opt/uactions/scripts/app/"
  mv -f /tmp/deploy-container.sh /opt/uactions/scripts/app/deploy-container.sh
  chmod +x /opt/uactions/scripts/app/deploy-container.sh
fi

# --- Export Deployment Variables -----------------------------------------------------
echo "📤 Exporting deployment variables..."

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

# --- Execute Deployment ---------------------------------------------------------------
echo "🚀 Executing deployment script..."
echo "  Script: /opt/uactions/scripts/app/deploy-container.sh"
echo "  App: $APP_SLUG"
echo "  Env: $ENV_NAME"
echo "  Image: $IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  Traefik: $TRAEFIK_ENABLED"

/opt/uactions/scripts/app/deploy-container.sh

echo "✅ Deployment completed successfully"
