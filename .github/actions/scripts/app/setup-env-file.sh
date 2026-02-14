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

# Final ownership normalization: even when the directory is already writable
# (for example 0777 but still owned by root), ensure any existing files inside
# the deployment root are owned by the SSH user so they can be read and updated
# without manual chmod/chown on each deploy.
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
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

# When a fresh env payload is provided, overwrite the env file *before* sourcing
# so stale or invalid content cannot cause the shell to fail prior to the update.
if [ -n "$ENV_B64" ] || [ -n "$ENV_CONTENT" ]; then
  echo " Preparing to write env file"
  echo "================================================================"
  echo "  • Target: $ENV_FILE"
  echo "  • Directory: $ENV_DIR"
  
  # Ensure the directory exists before writing
  if [ ! -d "$ENV_DIR" ]; then
    echo "  • Creating directory: $ENV_DIR"
    mkdir -p "$ENV_DIR" || {
      echo "::error::Failed to create directory: $ENV_DIR" >&2
      exit 1
    }
  fi
  
  if [ -n "$ENV_B64" ]; then
    echo "  • Source: base64 payload (${#ENV_B64} chars)"
    # Validate base64 before writing
    if ! printf '%s' "$ENV_B64" | base64 -d > /dev/null 2>&1; then
      echo "::error::ENV_B64 contains invalid base64 data" >&2
      exit 1
    fi
    printf '%s' "$ENV_B64" | base64 -d > "$ENV_FILE"
    WRITE_STATUS=$?
  else
    echo "  • Source: raw content (${#ENV_CONTENT} chars)"
    printf '%s' "$ENV_CONTENT" > "$ENV_FILE"
    WRITE_STATUS=$?
  fi
  
  if [ $WRITE_STATUS -ne 0 ]; then
    echo "::error::Failed to write environment file to $ENV_FILE" >&2
    exit 1
  fi
  
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
  
  # Sync to ensure data is written to disk (important for container reads)
  sync "$ENV_FILE" 2>/dev/null || sync 2>/dev/null || true
  
  # Verify the file was written
  if [ -f "$ENV_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$ENV_FILE" 2>/dev/null || stat -f%z "$ENV_FILE" 2>/dev/null || echo "unknown")
    echo "  • File written successfully (${FILE_SIZE} bytes)"
    
    # Verify file is not empty (unless that's intended)
    if [ "$FILE_SIZE" = "0" ] || [ "$FILE_SIZE" = "unknown" ]; then
      echo "  ⚠ Warning: Environment file appears to be empty"
    fi
  else
    echo "::error::Environment file was not created at $ENV_FILE" >&2
    exit 1
  fi

  # -----------------------------------------------------------------------------
  # ENV FILE SANITIZATION
  # -----------------------------------------------------------------------------
  # Purpose: Ensure values with spaces or special characters are properly quoted
  # so the file can be sourced by bash without interpreting unquoted words as
  # commands. Example problem: ZEPTO_DEFAULT_FROM_NAME=David from EventKaban
  # would cause "from: command not found" because bash sees "from" as a command.
  #
  # This sanitizer:
  #   - Skips empty lines and comment lines (# ...)
  #   - Skips lines already containing quotes (single or double)
  #   - Wraps values containing spaces, $, `, !, or other shell metacharacters
  #     in double quotes
  #   - Preserves lines that are already safe (simple KEY=value without spaces)
  # -----------------------------------------------------------------------------
  if [ -f "$ENV_FILE" ]; then
    ENV_FILE_TMP="${ENV_FILE}.sanitized"
    while IFS= read -r line || [ -n "$line" ]; do
      # Pass through empty lines and comments unchanged
      case "$line" in
        ''|\#*)
          printf '%s\n' "$line"
          continue
          ;;
      esac

      # Skip lines that already have quotes (user explicitly quoted)
      case "$line" in
        *\'*|*\"*)
          printf '%s\n' "$line"
          continue
          ;;
      esac

      # Split into KEY and VALUE at first '='
      key="${line%%=*}"
      value="${line#*=}"

      # If no '=' found, pass through unchanged (malformed line)
      if [ "$key" = "$line" ]; then
        printf '%s\n' "$line"
        continue
      fi

      # Check if value needs quoting (contains space, tab, $, `, !, (, ), etc.)
      # Using case pattern matching for POSIX compatibility
      needs_quote=false
      case "$value" in
        *\ *|*\	*|*\$*|*\`*|*\!*|*\(*|*\)*|*\;*|*\&*|*\|*|*\<*|*\>*|*\"*|*\'*)
          needs_quote=true
          ;;
      esac

      if $needs_quote; then
        # Escape any existing double quotes and backslashes in value
        escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '%s="%s"\n' "$key" "$escaped_value"
      else
        printf '%s\n' "$line"
      fi
    done < "$ENV_FILE" > "$ENV_FILE_TMP"
    mv "$ENV_FILE_TMP" "$ENV_FILE"
    chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
    echo "  • Environment file sanitized (values with spaces quoted)"
  fi

  echo "  • Environment file written to $ENV_FILE (600)"
  echo "================================================================"
  echo ""
else
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "ℹ️  No ENV_B64/ENV_CONTENT provided; leaving existing $ENV_FILE as-is"
  fi
fi

# Source environment variables if file exists (using the freshly written file
# when ENV_B64/ENV_CONTENT was provided).
if [ -f "$ENV_FILE" ]; then
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "🔄 Sourcing environment variables from $ENV_FILE"
  fi
  
  # Verify file is readable
  if [ ! -r "$ENV_FILE" ]; then
    echo "::error::Environment file $ENV_FILE exists but is not readable" >&2
    exit 1
  fi
  
  # When run under a parent script that enables `set -u` (nounset), a single
  # reference to an undefined variable inside the .env file (for example,
  # PASSWORD=$MISSING_SECRET) would normally abort the entire deployment.
  # To keep .env semantics closer to typical dotenv loaders (unset → empty)
  # while preserving strict mode for the rest of the deployment, temporarily
  # relax nounset while sourcing and then restore its previous state.
  nounset_was_on=false
  if set -o | grep -q 'nounset[[:space:]]*on'; then
    nounset_was_on=true
    set +u
  fi

  set -a
  # Source the file and capture any errors
  if ! . "$ENV_FILE"; then
    echo "::error::Failed to source environment file $ENV_FILE" >&2
    if [ "$nounset_was_on" = true ]; then
      set -u
    fi
    exit 1
  fi
  set +a

  if [ "$nounset_was_on" = true ]; then
    set -u
  fi
  
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "  ✓ Environment sourced successfully"
    # Count variables that were set
    ENV_VAR_COUNT=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" 2>/dev/null || echo "0")
    echo "  • Approximately $ENV_VAR_COUNT variables loaded"
  fi
else
  echo "::warning::Environment file $ENV_FILE not found; continuing without sourcing"
fi


if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "� Using prepared environment directory: $ENV_DIR"
  echo "📄 Using env file: $ENV_FILE"
fi


# Export variables for downstream scripts
export REMOTE_ENV_DIR="$ENV_DIR"
export REMOTE_ENV_FILE="$ENV_FILE"
export REMOTE_DEPLOYMENT_DIR
