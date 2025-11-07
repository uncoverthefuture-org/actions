#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# run-env-setup.sh - Environment setup and file management runner
# ----------------------------------------------------------------------------
# Purpose:
#   Handles environment directory creation, file writing, and sourcing
#   for deployment operations. Replaces long inline scripts in GitHub Actions.
#
# Inputs (environment variables):
#   ENV_FILE_PATH           - Path to the .env file to write
#   ENV_B64                 - Base64 encoded environment content
#   ENV_CONTENT             - Raw environment content (alternative to ENV_B64)
#   GITHUB_REF_NAME         - GitHub ref name for env detection
#   GITHUB_REPOSITORY       - GitHub repository for app slug derivation
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail

# --- Resolve inputs -----------------------------------------------------------------
# Get required environment variables with defaults
ENV_FILE_PATH="${ENV_FILE_PATH:-}"
ENV_B64="${ENV_B64:-}"
ENV_CONTENT="${ENV_CONTENT:-}"

# --- Environment Setup ---------------------------------------------------------------
echo "🔧 Setting up environment management..."

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

# Determine environment name from GitHub ref if not embedded in path
if [[ "$ENV_FILE_PATH" =~ /([^/]+)/([^/]+)/\.env$ ]]; then
  ENV_NAME="${BASH_REMATCH[1]}"
  APP_SLUG="${BASH_REMATCH[2]}"
else
  # Fallback to detecting from GitHub context
  REF_NAME="${GITHUB_REF_NAME:-}"
  case "$REF_NAME" in
    main|master|production) ENV_NAME='production' ;;
    stage|staging) ENV_NAME='staging' ;;
    dev|develop|development) ENV_NAME='development' ;;
    refs/tags/*) ENV_NAME='production' ;;
    *) ENV_NAME='development' ;;
  esac

  # Determine app slug from GitHub repository
  REPO_NAME_RAW="${GITHUB_REPOSITORY:-}"
  if [ -n "$REPO_NAME_RAW" ]; then
    REPO_NAME="${REPO_NAME_RAW##*/}"
  else
    REPO_NAME='app'
  fi
  APP_SLUG=$(printf '%s' "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
fi

# Setup environment directories and files
# Default to a user-owned base under the REMOTE $HOME to avoid permission issues
# (callers typically pass an explicit ENV_FILE_PATH; this default is a safe fallback)
ENV_ROOT_DEFAULT="${HOME}/deployments"
ENV_ROOT="${ENV_FILE_PATH_BASE:-$ENV_ROOT_DEFAULT}"
ENV_DIR="${ENV_ROOT}/${ENV_NAME}/${APP_SLUG}"

# Prepare environment directory; if not writable, fix ownership once via sudo
echo "📁 Preparing environment directory: $ENV_DIR"
if [ -d "$ENV_DIR" ] && [ ! -w "$ENV_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
if [ ! -d "$ENV_DIR" ]; then
  # Create env dir; on failure, escalate with sudo and set ownership back to user
  if ! mkdir -p "$ENV_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo mkdir -p "$ENV_DIR" 2>/dev/null || true
      sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
    else
      echo "::error::Unable to create env directory $ENV_DIR" >&2
      echo "Hint: ensure the SSH user owns the parent directory or choose a user-writable location." >&2
      exit 1
    fi
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  # Last attempt to fix ownership so further writes succeed
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: run 'chown -R $CURRENT_USER $ENV_DIR' on the host or pick a user-owned path." >&2
  exit 1
fi

# Use provided ENV_FILE_PATH or construct default
if [ -z "$ENV_FILE_PATH" ]; then
  ENV_FILE_PATH="${ENV_DIR}/.env"
fi

# Normalize explicit ENV_FILE_PATH from callers to the REMOTE $HOME
# - Expand ~ to $HOME
# - Rebase /home/runner to $HOME (avoid runner HOME leaking to remote)
case "$ENV_FILE_PATH" in
  "~/"*) ENV_FILE_PATH="$HOME/${ENV_FILE_PATH#~/}" ;;
  "/home/runner/"*) ENV_FILE_PATH="$HOME/${ENV_FILE_PATH#/home/runner/}" ;;
esac
ENV_FILE="$ENV_FILE_PATH"

ENV_PARENT_DIR="$(dirname "$ENV_FILE")"
if [ ! -d "$ENV_PARENT_DIR" ]; then
  # Ensure parent dir exists; fallback to sudo + chown for non-writable parents
  if ! mkdir -p "$ENV_PARENT_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo mkdir -p "$ENV_PARENT_DIR" 2>/dev/null || true
      sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_PARENT_DIR" 2>/dev/null || true
    else
      echo "::error::Unable to create parent directory $ENV_PARENT_DIR" >&2
      exit 1
    fi
  fi
fi
if [ ! -w "$ENV_PARENT_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_PARENT_DIR" 2>/dev/null || true
  fi
fi
if [ ! -w "$ENV_PARENT_DIR" ]; then
  echo "::error::Directory $ENV_PARENT_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: adjust permissions or choose a path under $HOME." >&2
  exit 1
fi

# Create env file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
  echo "📄 Creating environment file: $ENV_FILE"
  {
    printf '# Generated by uactions package (run-env-setup.sh).\n'
    printf '# Populate with KEY=VALUE pairs required for your deployment.\n'
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
else
  echo "📄 Environment file already exists: $ENV_FILE"
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
echo "📦 Staging environment scripts..."
cd /

# Ensure scripts directory exists
mkdir -p "$HOME/uactions/scripts/app"

# Move uploaded env script if it exists
if [ -f /tmp/write-env-file.sh ]; then
  echo "📋 Moving write-env-file.sh to $HOME/uactions/scripts/app/"
  mv -f /tmp/write-env-file.sh "$HOME/uactions/scripts/app/write-env-file.sh"
  chmod +x "$HOME/uactions/scripts/app/write-env-file.sh"
fi

# --- Export Environment Variables -----------------------------------------------------
echo "📤 Exporting environment variables..."

# Environment file settings
export ENV_FILE_PATH
export ENV_B64
export ENV_CONTENT

# --- Execute Environment Setup -------------------------------------------------------
echo "🚀 Executing environment setup script..."
echo "  Script: $HOME/uactions/scripts/app/write-env-file.sh"
echo "  Env file: $ENV_FILE_PATH"

"$HOME/uactions/scripts/app/write-env-file.sh"

echo "✅ Environment setup completed successfully"
