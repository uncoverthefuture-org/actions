#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# deploy-container.sh
# ----------------------------------------------------------------------------
# Purpose:
#   Run or replace an application container via Podman, with optional Traefik
#   routing. Designed to be called from CI after env file and image are ready.
#
# Inputs (environment variables):
#   IMAGE_REGISTRY        - Registry host (default: ghcr.io)
#   IMAGE_NAME            - Image path (org/repo) [REQUIRED]
#   IMAGE_TAG             - Image tag (default: latest)
#   APP_SLUG              - App slug used in default names/paths [REQUIRED]
#   ENV_NAME              - Environment name (production|staging|development) [REQUIRED]
#   CONTAINER_NAME_IN     - Optional container name override; default <app_slug>-<env>
#   ENV_FILE_PATH_BASE    - Base dir for env files; default /var/deployments
#   HOST_PORT_IN          - Optional host port (when Traefik disabled)
#   CONTAINER_PORT_IN     - Optional container port (service port for Traefik or mapping)
#   EXTRA_RUN_ARGS        - Extra args appended to podman run
#   DEPLOY_DIR_VOLUME_ENABLED - Toggle automatic mount of deployment dir (default: true)
#   DEPLOY_DIR_CONTAINER_PATH - Target path inside container for deployment dir (default: /<app_slug>)
#   RESTART_POLICY        - Podman restart policy (default: unless-stopped)
#   MEMORY_LIMIT          - Memory and swap (default: 512m)
#   CPU_LIMIT             - CPU limit (default: 0.5) passed as --cpus to podman
#   TRAEFIK_ENABLED       - 'true' to attach labels (requires DOMAIN)
#   DOMAIN_INPUT          - Explicit FQDN
#   DOMAIN_DEFAULT        - Derived FQDN
#   ROUTER_NAME           - Traefik router/service name slug
#   REMOTE_ENV_FILE       - (Optional) Path to .env provided by runner wrapper
#
# Behavior:
#   - Computes ENV_FILE if not given and falls back to /var/deployments/<env>/<app>/.env
#   - Computes CONTAINER_NAME if not provided
#   - Computes HOST_PORT, CONTAINER_PORT using provided inputs or sourced env vars
#   - If TRAEFIK_ENABLED and DOMAIN present, sets Traefik labels; else publishes -p host:container
# ----------------------------------------------------------------------------
set -euo pipefail

# Shared helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../util/ports.sh
source "${SCRIPT_DIR}/../util/ports.sh"
# shellcheck source=../util/validate.sh
source "${SCRIPT_DIR}/../util/validate.sh"
# shellcheck source=../util/normalize.sh
source "${SCRIPT_DIR}/../util/normalize.sh"
# shellcheck source=../util/traefik.sh
source "${SCRIPT_DIR}/../util/traefik.sh"
# shellcheck source=../util/podman.sh
source "${SCRIPT_DIR}/../util/podman.sh"

# --- Resolve inputs -----------------------------------------------------------------
SUDO_STATUS="${SUDO_STATUS:-available}"

# --- Image & registry inputs --------------------------------------------------------
IMAGE_REGISTRY_RAW="${IMAGE_REGISTRY:-ghcr.io}"
IMAGE_REGISTRY=$(normalize_string "$IMAGE_REGISTRY_RAW" "image registry")
IMAGE_NAME_RAW="${IMAGE_NAME:-}"
IMAGE_NAME=$(normalize_string "$IMAGE_NAME_RAW" "image name")
IMAGE_TAG="${IMAGE_TAG:-latest}"

# --- Application & environment metadata --------------------------------------------
APP_SLUG_RAW="${APP_SLUG:-}"
APP_SLUG=$(normalize_string "$APP_SLUG_RAW" "app slug")
ENV_NAME_RAW="${ENV_NAME:-}"
ENV_NAME=$(normalize_string "$ENV_NAME_RAW" "env name")
CONTAINER_NAME_IN="${CONTAINER_NAME_IN:-}"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-${HOME}/deployments}"

# --- Runtime configuration ---------------------------------------------------------
HOST_PORT_IN="${HOST_PORT_IN:-}"
CONTAINER_PORT_IN="${CONTAINER_PORT_IN:-}"
EXTRA_RUN_ARGS="${EXTRA_RUN_ARGS:-}"
RESTART_POLICY="${RESTART_POLICY:-unless-stopped}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
CPU_LIMIT="${CPU_LIMIT:-0.5}"
DEPLOY_DIR_VOLUME_ENABLED="${DEPLOY_DIR_VOLUME_ENABLED:-true}"
if [[ -z "${DEPLOY_DIR_CONTAINER_PATH:-}" ]]; then
  DEPLOY_DIR_CONTAINER_PATH="/${APP_SLUG}"
else
  DEPLOY_DIR_CONTAINER_PATH="${DEPLOY_DIR_CONTAINER_PATH}"
fi
if [[ "$DEPLOY_DIR_CONTAINER_PATH" == "/" ]]; then
  # Inline doc: Podman (especially rootless) refuses mounting directories at container
  # root. Example: set DEPLOY_DIR_CONTAINER_PATH=/srv/app to expose the deployment at
  # /srv/app inside the container instead of attempting to mount to '/'.
  echo "::warning::DEPLOY_DIR_CONTAINER_PATH='/' is not supported; defaulting to /${APP_SLUG}" >&2
  DEPLOY_DIR_CONTAINER_PATH="/${APP_SLUG}"
fi
DEPLOY_DIR_HOST_PATH="${DEPLOY_DIR_HOST_PATH:-}"

# --- Traefik & domain routing ------------------------------------------------------
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
DOMAIN_INPUT="${DOMAIN_INPUT:-}"
DOMAIN_DEFAULT="${DOMAIN_DEFAULT:-}"
ROUTER_NAME="${ROUTER_NAME:-app}"

# Collect required fields and validate via shared helper (example: ensure
# IMAGE_NAME, APP_SLUG, ENV_NAME are set before proceeding).
# Example:
#   declare -A cfg=([APP_SLUG]="demo" [ENV_NAME]="production");
#   validate_required cfg APP_SLUG ENV_NAME
declare -A config=(
  [IMAGE_NAME]="${IMAGE_NAME:-}"
  [APP_SLUG]="${APP_SLUG:-}"
  [ENV_NAME]="${ENV_NAME:-}"
)

# Validate required keys
validate_required config IMAGE_NAME APP_SLUG ENV_NAME
echo "================================================================"
echo "🔧 Preparing deploy"
echo "================================================================"
echo "  • App:        $APP_SLUG"
echo "  • Env:        $ENV_NAME"
echo "  • Image:      ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# --- Compute names and paths --------------------------------------------------------
# Derive final container name: honor explicit input but fall back to
# <app-slug>-<env> when unset so multiple environments coexist predictably.
CONTAINER_NAME="$CONTAINER_NAME_IN"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="${APP_SLUG}-${ENV_NAME}"
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  # Example: DEBUG=true APP_SLUG=demo ENV_NAME=staging prints "demo-staging"
  echo "================================================================"
  echo "📛 Container name: $CONTAINER_NAME"
  echo "================================================================"
fi

# Environment directory and file are prepared by run-deployment/setup-env-file.
# These exports ensure downstream scripts operate on the same resolved paths.
ENV_DIR="${REMOTE_ENV_DIR:-}"
ENV_FILE="${REMOTE_ENV_FILE:-}"

# Verify and source the environment file if available
if [[ -z "$ENV_DIR" || -z "$ENV_FILE" ]]; then
  echo "================================================================" >&2
  echo "::warning::Remote environment payload missing" >&2
  echo "  • REMOTE_ENV_DIR='${REMOTE_ENV_DIR:-}'" >&2
  echo "  • REMOTE_ENV_FILE='${REMOTE_ENV_FILE:-}'" >&2
  echo "  • ENV_B64='${ENV_B64:-<empty>}' / ENV_CONTENT='${ENV_CONTENT:-<empty>}'" >&2
  echo "  → Attempting to resolve env file from deployment directory..." >&2
  echo "================================================================" >&2
  
  # Attempt to reconstruct ENV_DIR and ENV_FILE from known values
  if [[ -n "$APP_SLUG" && -n "$ENV_NAME" ]]; then
    ENV_DIR="${HOME}/deployments/${ENV_NAME}/${APP_SLUG}"
    ENV_FILE="${ENV_DIR}/.env"
    echo "  → Resolved fallback path: $ENV_FILE" >&2
  fi
fi

# Verify the env file exists and source it
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "================================================================" >&2
  echo "📄 Loading environment from: $ENV_FILE" >&2
  
  # Show file info for debugging
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "  • File size: $(stat -c%s "$ENV_FILE" 2>/dev/null || stat -f%z "$ENV_FILE" 2>/dev/null || echo "unknown") bytes" >&2
    echo "  • Last modified: $(stat -c%y "$ENV_FILE" 2>/dev/null || stat -f%Sm "$ENV_FILE" 2>/dev/null || echo "unknown")" >&2
  fi
  
  # Source the environment file to ensure all variables are loaded
  # Use set -a to export all variables automatically
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE" || {
    echo "::warning::Failed to source environment file: $ENV_FILE" >&2
  }
  set +a
  
  echo "  ✓ Environment loaded successfully" >&2
  echo "================================================================" >&2
else
  echo "================================================================" >&2
  echo "::warning::Environment file not found or not specified" >&2
  if [[ -n "$ENV_FILE" ]]; then
    echo "  • Expected path: $ENV_FILE" >&2
    echo "  • Directory exists: $([[ -d "$(dirname "$ENV_FILE")" ]] && echo 'yes' || echo 'no')" >&2
  fi
  echo "================================================================" >&2
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  # Confirm to operators which directory/file the script will mutate.
  echo "🗂️  Using prepared environment directory: $ENV_DIR"
  echo "📄 Using env file: $ENV_FILE"
fi

# Persisted host-port assignments live alongside the env file; track whether
# the script auto-selects a port so we can emit guidance at the end.
HOST_PORT_FILE="${ENV_DIR}/.host-port"
AUTO_HOST_PORT_ASSIGNED=false


# If host prep will run, let install-podman handle the privilege check and messaging
echo "================================================================"
echo "📛 Confirming podman installation..."
echo "================================================================"
# If podman exists, continue
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
    echo 'Or re-run this action with prepare_host: true and root privileges.' >&2
    exit 1
  else
    # Use --allow-releaseinfo-change so noninteractive runs do not fail when a
    # trusted repository (for example, the ondrej/php PPA) updates its Release
    # metadata fields such as Label or Suite.
    echo "   Running (sudo apt-get update -y --allow-releaseinfo-change)"
    if sudo apt-get update -y --allow-releaseinfo-change; then
      echo "   ✅ apt-get update completed"
    else
      echo "::error::apt-get update failed" >&2
      return 1
    fi

    echo "   Running (sudo apt-get install -y podman curl jq ca-certificates)"
    if sudo apt-get install -y podman curl jq ca-certificates; then
      echo "   ✅ Podman and dependencies installed"
    else
      echo "::error::apt-get install podman curl jq ca-certificates failed" >&2
      return 1
    fi
  fi
fi

echo "================================================================"
echo "🔌 Ensuring podman socket is active"
echo "================================================================"
if [[ "${SUDO_STATUS:-available}" == "unavailable" ]]; then
  echo "::error::sudo privileges required to enable podman.socket" >&2
  exit 1
fi

if sudo systemctl enable --now podman.socket >/dev/null 2>&1; then
  echo "✅ podman.socket enabled"
else
  echo "::error::Unable to enable podman.socket" >&2
  exit 1
fi

# --- Detect Traefik availability -----------------------------------------------------
echo "================================================================"
echo "🛰  Probing for Traefik runtime"
echo "================================================================"
TRAEFIK_PRESENT=$(podman_detect_traefik && echo true || echo false)

# --- Inspect existing container for port reuse --------------------------------------
# Check whether the target container already exists so we can harvest prior
# port assignments and label data before replacing it.
EXISTING=false
if run_podman container exists "$CONTAINER_NAME" >/dev/null 2>&1; then
  EXISTING=true
fi

# --- Compute ports ------------------------------------------------------------------
# Prefer provided inputs; otherwise reuse from existing container; otherwise defaults

# Container port resolution (labels for Traefik or env fallbacks)
# Step 1: reuse shared resolver to keep behavior consistent across scripts.
CONTAINER_PORT="$(podman_resolve_container_port "$CONTAINER_PORT_IN" "$TRAEFIK_ENABLED" "$ROUTER_NAME" "$CONTAINER_NAME" "${DEBUG:-false}")" || exit 1

# Host port resolution (reuse prior mapping; persisted fallback; final default 8080)
read HOST_PORT HOST_PORT_SOURCE AUTO_HOST_PORT_ASSIGNED <<<"$(podman_resolve_host_port "$HOST_PORT_IN" "$CONTAINER_NAME" "$CONTAINER_PORT" "$HOST_PORT_FILE" "${DEBUG:-false}")" || exit 1

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "🌐 Service target port (container): $CONTAINER_PORT"
  echo "🌐 Host port candidate: $HOST_PORT (source: ${HOST_PORT_SOURCE:-manual})"
fi

# --- Prepare run args ---------------------------------------------------------------
# Compose the full image reference and allocate arrays that will accumulate
# `podman run` arguments derived from Traefik, port publishing, DNS, etc.
IMAGE_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PORT_ARGS=()
LABEL_ARGS=()
VOLUME_ARGS=()

DOMAIN="$DOMAIN_INPUT"
if [[ -z "$DOMAIN" ]]; then DOMAIN="$DOMAIN_DEFAULT"; fi

TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-}"
if [[ "$TRAEFIK_ENABLED" == "true" && -z "$TRAEFIK_NETWORK_NAME" ]]; then
  TRAEFIK_NETWORK_NAME="traefik-network"
fi

# When routing to an apex (base) domain like example.com, auto-include
# the www alias so both example.com and www.example.com route to the
# same container and ACME can validate both, unless the caller provided
# explicit DOMAIN_HOSTS (which takes precedence).
INCLUDE_WWW_ALIAS_EFF="${INCLUDE_WWW_ALIAS:-false}"
if [[ -z "${DOMAIN_HOSTS:-}" ]]; then
  dom_lower="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
  IFS='.' read -r -a parts <<<"$dom_lower"; count=${#parts[@]}
  if (( count >= 2 )); then
    apex="${parts[count-2]}.${parts[count-1]}"
    if [[ "$dom_lower" = "$apex" ]]; then
      INCLUDE_WWW_ALIAS_EFF="true"
    fi
  fi
fi

if [[ "$TRAEFIK_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔀 Traefik mode for domain (router: $ROUTER_NAME)"
    echo "🔖 Traefik labels will advertise container port $CONTAINER_PORT"
  fi
  echo "🌍 Resolved domain (effective): $DOMAIN"
  if [[ -x "$HOME/uactions/scripts/app/build-traefik-labels.sh" ]]; then
    TRAEFIK_ENABLE_ACME_EFF="${TRAEFIK_ENABLE_ACME:-true}"
    mapfile -t BUILT_LABELS < <( \
      ROUTER_NAME="$ROUTER_NAME" \
      DOMAIN="$DOMAIN" \
      CONTAINER_PORT="$CONTAINER_PORT" \
      ENABLE_ACME="$TRAEFIK_ENABLE_ACME_EFF" \
      DOMAIN_HOSTS="${DOMAIN_HOSTS:-}" \
      DOMAIN_ALIASES="${DOMAIN_ALIASES:-${ALIASES:-}}" \
      INCLUDE_WWW_ALIAS="$INCLUDE_WWW_ALIAS_EFF" \
      "$HOME/uactions/scripts/app/build-traefik-labels.sh"
    )
    RULE_LABEL=""
    for val in "${BUILT_LABELS[@]}"; do
      if [[ "$val" == traefik.http.routers."${ROUTER_NAME}".rule=* ]]; then
        RULE_LABEL="$val"; break
      fi
    done
    if [[ -n "$RULE_LABEL" ]]; then
      RULE_EXPR="${RULE_LABEL#*=}"
      echo "🧭 Traefik rule: ${RULE_EXPR}"
      HOSTS_PARSED=$(printf '%s\n' "$RULE_EXPR" | grep -Eo 'Host\("[^"]+"\)' | sed -E 's/^Host\("//' | sed -E 's/"\)$//' | tr '\n' ' ' | sed 's/ *$//')
      if [[ -n "$HOSTS_PARSED" ]]; then
        echo "🧭 Hosts configured: ${HOSTS_PARSED}"
        case " ${HOSTS_PARSED} " in
          *" ${DOMAIN} "*) ;;
          *) echo "::warning::Effective domain '${DOMAIN}' not present in Traefik rule hosts" ;;
        esac
      fi
    fi
    LABEL_ARGS+=("${BUILT_LABELS[@]}")
    if [[ -n "$TRAEFIK_NETWORK_NAME" ]]; then
      LABEL_ARGS+=(--label "traefik.docker.network=${TRAEFIK_NETWORK_NAME}")
    fi
  else
    # Fallback path: build labels via shared helper for consistency
    mapfile -t FALLBACK_LABELS < <(build_traefik_labels_fallback "$ROUTER_NAME" "$DOMAIN" "$CONTAINER_PORT" "${TRAEFIK_ENABLE_ACME_EFF}" "${DOMAIN_HOSTS:-}" "${DOMAIN_ALIASES:-${ALIASES:-}}" "$INCLUDE_WWW_ALIAS_EFF" "${TRAEFIK_NETWORK_NAME:-}")
    LABEL_ARGS+=("${FALLBACK_LABELS[@]}")
  fi
else
  echo "ℹ️  Traefik disabled; container will rely on host port mapping"
fi

# Determine port mapping strategy based on Traefik configuration.
if [[ "$TRAEFIK_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  # Traefik handles ingress; no need to publish host ports.
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔒 Skipping host port publish (Traefik handles ingress on 80/443)"
  fi
  PORT_ARGS=()
else
  # Publish port mapping for direct access.
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔓 Publishing port mapping"
  fi
  PORT_ARGS=(-p "${HOST_PORT}:${CONTAINER_PORT}")
fi

# Automatically mount the deployment directory into the container unless disabled.
# Default host path is the prepared REMOTE_ENV_DIR; callers can override with
# DEPLOY_DIR_HOST_PATH or set DEPLOY_DIR_VOLUME_ENABLED=false to skip.
if [[ "${DEPLOY_DIR_VOLUME_ENABLED,,}" == "true" ]]; then
  DEPLOY_DIR_SOURCE="$DEPLOY_DIR_HOST_PATH"
  if [[ -z "$DEPLOY_DIR_SOURCE" ]]; then
    DEPLOY_DIR_SOURCE="${REMOTE_DEPLOYMENT_DIR:-${ENV_DIR}}"
  elif [[ "$DEPLOY_DIR_SOURCE" != /* ]]; then
    DEPLOY_DIR_SOURCE="${REMOTE_DEPLOYMENT_DIR:-${ENV_DIR}}/${DEPLOY_DIR_SOURCE}"
  fi

  if [[ -z "$DEPLOY_DIR_SOURCE" ]]; then
    echo "::warning::Deployment directory mount enabled but no source path available; skipping." >&2
  elif [[ -d "$DEPLOY_DIR_SOURCE" ]]; then
    VOLUME_ARGS+=(-v "${DEPLOY_DIR_SOURCE}:${DEPLOY_DIR_CONTAINER_PATH}")
    if [[ "${DEBUG:-false}" == "true" ]]; then
      echo "🗂️  Mounting deployment directory ${DEPLOY_DIR_SOURCE} -> ${DEPLOY_DIR_CONTAINER_PATH}"
    fi
  else
    echo "::warning::Deployment directory ${DEPLOY_DIR_SOURCE} not found; skipping volume mount." >&2
  fi
else
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🗂️  Deployment directory mount disabled by DEPLOY_DIR_VOLUME_ENABLED=$DEPLOY_DIR_VOLUME_ENABLED"
  fi
fi

# --- Mount .env file explicitly for frameworks that expect it at app root --------
# Many frameworks (Laravel, Django, etc.) expect .env at the application root.
# This ensures the env file is available even if the deployment directory mount
# doesn't place it in the correct location.
ENV_FILE_MOUNT_ENABLED="${ENV_FILE_MOUNT_ENABLED:-true}"
ENV_FILE_CONTAINER_PATH="${ENV_FILE_CONTAINER_PATH:-/var/www/html/.env}"

if [[ "$ENV_FILE_MOUNT_ENABLED" == "true" && -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "📄 Mounting environment file: ${ENV_FILE} -> ${ENV_FILE_CONTAINER_PATH}" >&2
  VOLUME_ARGS+=(-v "${ENV_FILE}:${ENV_FILE_CONTAINER_PATH}:ro")
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "  • Host env file size: $(stat -c%s "$ENV_FILE" 2>/dev/null || stat -f%z "$ENV_FILE" 2>/dev/null || echo 'unknown') bytes" >&2
    echo "  • Mounted as read-only to prevent container modifications" >&2
  fi
elif [[ "$ENV_FILE_MOUNT_ENABLED" == "true" && -n "$ENV_FILE" ]]; then
  echo "::warning::ENV_FILE_MOUNT_ENABLED=true but env file not found at: ${ENV_FILE}" >&2
fi

# --- Login and pull (optional login, always pull) -----------------------------------
# Authenticate with the registry when credentials exist, then ensure the latest
# image is available locally. Consider relocating this block into a shared
# util/registry.sh for reuse by other deployment scripts.
if [[ "${REGISTRY_LOGIN:-true}" == "true" ]]; then
  podman_login_if_credentials "$IMAGE_REGISTRY" "${REGISTRY_USERNAME:-}" "${REGISTRY_TOKEN:-}"
fi
podman_pull_image "$IMAGE_REF"

# --- Stop/replace container ---------------------------------------------------------
# Cleanly stop and remove the prior container instance so the new one can start
# without conflicting names or port bindings.
echo "================================================================" >&2
echo "🛑 Stopping existing container (if any): $CONTAINER_NAME"
podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing existing container (if any): $CONTAINER_NAME"
podman rm   "$CONTAINER_NAME" >/dev/null 2>&1 || true
if podman container exists "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "::warning::Container '$CONTAINER_NAME' still exists after stop/rm; attempting force removal" >&2
  podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# --- Run container -----------------------------------------------------------------
echo "🚀 Starting container: $CONTAINER_NAME"
echo "================================================================" >&2

echo "Ensuring traefik-network is settup!";
NETWORK_ARGS=()
if [[ "$TRAEFIK_ENABLED" == "true" && -n "$TRAEFIK_NETWORK_NAME" ]]; then
  echo "Creating/ensuring Traefik network: $TRAEFIK_NETWORK_NAME"
  arg=$(ensure_traefik_network "$TRAEFIK_NETWORK_NAME" "${DEBUG:-false}")
  [[ -n "$arg" ]] && NETWORK_ARGS+=($arg)
fi
echo "================================================================" >&2


# --- DNS/Resolver handling --------------------------------------------------------
# Prefer mounting the host's real resolv.conf (systemd-resolved) so the container
# inherits accurate nameservers. If not readable/present, fallback to public DNS.
# Example:
#   - Mount: -v /run/systemd/resolve/resolv.conf:/etc/resolv.conf:ro
#   - Fallback: --dns 1.1.1.1 --dns 8.8.8.8
mapfile -t DNS_ARGS < <(podman_build_dns_args "${DEBUG:-false}")
echo "Port args: ${PORT_ARGS[*]}"
echo "DNS args: ${DNS_ARGS}"
echo "Network args: ${NETWORK_ARGS[*]}"
echo "Label args: ${LABEL_ARGS[*]}"
echo "Volume args: ${VOLUME_ARGS[*]}"

# Verify env file before passing to container
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "Env file: $ENV_FILE (exists)"
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "  • File contents preview (first 10 lines):" >&2
    head -n 10 "$ENV_FILE" | sed 's/=.*/=***/' >&2
  fi
else
  echo "Env file: $ENV_FILE (NOT FOUND - container may use default values)"
fi
echo "================================================================" >&2

# When CPU_LIMIT is provided, append an explicit --cpus constraint so the
# container cannot monopolize the host. Example: CPU_LIMIT=0.5 adds
#   --cpus=0.5
# to the podman run invocation assembled below.
if [[ -n "$CPU_LIMIT" ]]; then
  if podman_cpu_cgroup_available; then
    if [[ -n "$EXTRA_RUN_ARGS" ]]; then
      EXTRA_RUN_ARGS+=" --cpus=${CPU_LIMIT}"
    else
      EXTRA_RUN_ARGS="--cpus=${CPU_LIMIT}"
    fi
  else
    echo "::warning::CPU_LIMIT='${CPU_LIMIT}' configured but Podman host does not expose a 'cpu' cgroup controller; skipping --cpus (container will run without a CPU limit)." >&2
  fi
fi

# Assemble and execute podman run with a DEBUG preview via shared helper.
# Pass array *names* so the helper can dereference them (example: PORT_ARGS →
# publishes "-p 8080:3000" while an empty array stays omitted).
podman_run_with_preview "$CONTAINER_NAME" "$ENV_FILE" "$RESTART_POLICY" "$MEMORY_LIMIT" "$IMAGE_REF" "${EXTRA_RUN_ARGS:-}" "${DEBUG:-false}" \
  PORT_ARGS DNS_ARGS NETWORK_ARGS LABEL_ARGS VOLUME_ARGS
echo "================================================================" >&2
# --- Post status --------------------------------------------------------------------
# Provide immediate feedback showing the container status table so operators can
# verify the deployment succeeded without inspecting the remote host manually.
echo " Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}\t{{.Status}}\t{{.Image}}\t{{.Names}}\t{{.Ports}}'

# After a successful podman run, optionally generate a Quadlet .container unit
# so systemd --user can restart the app automatically on reboot using the
# same image, env file, ports, volume, and resource limits. This is a best
# effort step; failures are reported as warnings but do not fail the deploy.
#
# IMPORTANT: When TRAEFIK_ENABLED=true, we must also export Traefik routing
# variables (ROUTER_NAME, DOMAIN, TRAEFIK_ENABLE_ACME, etc.) so that the
# Quadlet unit includes the same Traefik labels as the initial deployment.
# Without these labels, containers restarted after reboot won't be discovered
# by Traefik and will return 404 errors.
if [[ -x "$HOME/uactions/scripts/app/install-app-quadlet.sh" ]]; then
  # Core container settings
  export IMAGE_REF
  export CONTAINER_NAME
  export HOST_PORT
  export CONTAINER_PORT
  export DEPLOY_DIR_SOURCE
  export DEPLOY_DIR_CONTAINER_PATH
  export MEMORY_LIMIT
  export CPU_LIMIT
  export APP_SLUG
  export ENV_NAME
  export REMOTE_ENV_FILE

  # Traefik routing settings - CRITICAL for post-reboot label generation
  # Without these, Quadlet units won't include Traefik labels and containers
  # will be invisible to Traefik after reboot, causing 404 errors.
  export TRAEFIK_ENABLED
  export TRAEFIK_NETWORK_NAME
  export ROUTER_NAME                                    # Router/service name for labels
  export DOMAIN                                         # Effective domain (computed above)
  export TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-true}"  # Whether TLS labels are needed
  export DOMAIN_HOSTS="${DOMAIN_HOSTS:-}"               # Explicit host list (optional)
  export DOMAIN_ALIASES="${DOMAIN_ALIASES:-}"           # Additional aliases (optional)
  export INCLUDE_WWW_ALIAS="${INCLUDE_WWW_ALIAS_EFF:-false}" # Include www variant

  export QUADLET_ENABLED="${QUADLET_ENABLED:-true}"
  "$HOME/uactions/scripts/app/install-app-quadlet.sh" || echo "::warning::install-app-quadlet.sh failed (Quadlet persistence may be unavailable)" >&2
else
  echo "::notice::install-app-quadlet.sh not found; skipping Quadlet persistence unit" >&2
fi
