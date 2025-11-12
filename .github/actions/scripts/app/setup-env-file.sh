# -----------------------------------------------------------------------------
# INPUT NORMALIZATION
# -----------------------------------------------------------------------------
# Purpose: gather all incoming variables with defaults so later sections can
# rely on normalized values without re-checking environment state.
# -----------------------------------------------------------------------------

# --- App & environment identifiers --------------------------------------------------
APP_SLUG="${APP_SLUG:-}"
ENV_NAME="${ENV_NAME:-}"
REF_NAME="${REF_NAME:-}"
REPO_NAME_RAW="${GITHUB_REPOSITORY:-}"

# --- Directory defaults -------------------------------------------------------------
ENV_B64="${ENV_B64:-}"
ENV_CONTENT="${ENV_CONTENT:-}"
ENV_ROOT_DEFAULT="${HOME}/deployments"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-$ENV_ROOT_DEFAULT}"
ENV_BASE_IN="${ENV_FILE_PATH_BASE:-$ENV_ROOT_DEFAULT}"

# --- Execution context --------------------------------------------------------------
CURRENT_USER="${CURRENT_USER:-$(id -un)}"

# -----------------------------------------------------------------------------
# ENVIRONMENT NAME DERIVATION
# -----------------------------------------------------------------------------
# Purpose: prefer explicit ENV_NAME, fall back to branch/tag heuristics so
# deployments remain consistent even when callers omit the environment input.
# -----------------------------------------------------------------------------


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

# -----------------------------------------------------------------------------
# APP SLUG RESOLUTION
# -----------------------------------------------------------------------------
# Purpose: ensure we always have an app slug compatible with directory names
# and Traefik router IDs by deriving it from the repository when unset.
# -----------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------
# DIRECTORY PREPARATION
# -----------------------------------------------------------------------------
# Purpose: sanitize the base path, create the environment directory hierarchy,
# and confirm the SSH user has ownership so downstream scripts can write .env
# content without sudo.
# -----------------------------------------------------------------------------

case "$ENV_BASE_IN" in
  "~/"*) ENV_ROOT="$HOME/${ENV_BASE_IN#~/}" ;;
  "/home/runner/"*) ENV_ROOT="$HOME/${ENV_BASE_IN#/home/runner/}" ;;
  *) ENV_ROOT="$ENV_BASE_IN" ;;
esac
ENV_DIR="${ENV_ROOT}/${ENV_NAME}/${APP_SLUG}"
# Canonical deployment directory used by other scripts for volume mounts.
if [ -z "${REMOTE_DEPLOYMENT_DIR:-}" ]; then
  REMOTE_DEPLOYMENT_DIR="$ENV_DIR"
fi

if [ "${DEBUG:-false}" = "true" ]; then
  echo "📁 Preparing environment directory"
fi
# If dir exists but is not writable, attempt to fix ownership once with sudo
if [ -d "$ENV_DIR" ] && [ ! -w "$ENV_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
# If still not writable, attempt to fix ownership with sudo; otherwise fail
if [ ! -d "$ENV_DIR" ]; then
  if ! mkdir -p "$ENV_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo mkdir -p "$ENV_DIR" 2>/dev/null || true
      sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
    else
      echo "::error::Unable to create environment directory" >&2
      echo "Hint: ensure the SSH user owns the parent directory or use a user-writable location." >&2
      exit 1
    fi
  fi
fi
# If still not writable, attempt to fix ownership with sudo; otherwise fail
if [ ! -w "$ENV_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: run 'chown -R $CURRENT_USER $ENV_DIR' on the host or select a user-owned path." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# ENV FILE BOOTSTRAP
# -----------------------------------------------------------------------------
# Purpose: guarantee an .env exists (when missing) and provide friendly
# comments so operators understand the file's provenance and usage.
# -----------------------------------------------------------------------------

ENV_FILE="${ENV_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "📄 Creating environment file"
  fi
  {
    printf '# Generated by uactions package (run-deployment.sh).\n'
    printf '# Populate with KEY=VALUE pairs required for your deployment.\n'
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
else
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "📄 Environment file already exists"
  fi
fi

# Source environment variables if file exists
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "🔄 Sourcing environment variables"
  fi
  set -a
  . "$ENV_FILE"
  set +a
else
  echo "::warning::Environment file $ENV_FILE not found; continuing without sourcing"
fi


if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "� Using prepared environment directory: $ENV_DIR"
  echo "📄 Using env file: $ENV_FILE"
fi


if [ -n "$ENV_B64" ] || [ -n "$ENV_CONTENT" ]; then
  echo " Preparing to write env file"
  echo "================================================================"
  echo "  • Target: $ENV_FILE"
  if [ -n "$ENV_B64" ]; then
    echo "  • Source: base64 payload (content will not be printed)"
    printf '%s' "$ENV_B64" | base64 -d > "$ENV_FILE"
  else
    echo "  • Source: raw content (content will not be printed)"
    printf '%s' "$ENV_CONTENT" > "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
  echo "  • Environment file written to $ENV_FILE (600)"
  echo "================================================================"
  echo ""
else
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "ℹ️  No ENV_B64/ENV_CONTENT provided; leaving existing $ENV_FILE as-is"
  fi
fi


# Export variables for downstream scripts
export REMOTE_ENV_DIR="$ENV_DIR"
export REMOTE_ENV_FILE="$ENV_FILE"
export REMOTE_DEPLOYMENT_DIR
