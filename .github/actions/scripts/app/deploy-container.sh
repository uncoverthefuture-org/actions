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
#   RESTART_POLICY        - Podman restart policy (default: unless-stopped)
#   MEMORY_LIMIT          - Memory and swap (default: 512m)
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

# --- Resolve inputs -----------------------------------------------------------------
IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"          # required
IMAGE_TAG="${IMAGE_TAG:-latest}"
APP_SLUG="${APP_SLUG:-}"              # required
ENV_NAME="${ENV_NAME:-}"              # required
CONTAINER_NAME_IN="${CONTAINER_NAME_IN:-}"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-${HOME}/deployments}"
HOST_PORT_IN="${HOST_PORT_IN:-}"
CONTAINER_PORT_IN="${CONTAINER_PORT_IN:-}"
EXTRA_RUN_ARGS="${EXTRA_RUN_ARGS:-}"
RESTART_POLICY="${RESTART_POLICY:-unless-stopped}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
DOMAIN_INPUT="${DOMAIN_INPUT:-}"
DOMAIN_DEFAULT="${DOMAIN_DEFAULT:-}"
ROUTER_NAME="${ROUTER_NAME:-app}"

if [[ -z "$IMAGE_NAME" || -z "$APP_SLUG" || -z "$ENV_NAME" ]]; then
  echo "Error: IMAGE_NAME, APP_SLUG, and ENV_NAME are required." >&2
  exit 1
fi

echo "🔧 Preparing deploy"

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

echo "  • App:        $APP_SLUG"
echo "  • Env:        $ENV_NAME"
echo "  • Image:      ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# --- Compute names and paths --------------------------------------------------------
CONTAINER_NAME="$CONTAINER_NAME_IN"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="${APP_SLUG}-${ENV_NAME}"
fi

echo "📛 Container name: $CONTAINER_NAME"

ENV_DIR="${ENV_FILE_PATH_BASE%/}/${ENV_NAME}/${APP_SLUG}"

echo "📁 Preparing environment directory: $ENV_DIR"
if [ -d "$ENV_DIR" ] && [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: create a user-owned path (e.g., $HOME/deployments) or adjust permissions." >&2
  exit 1
fi
if [ ! -d "$ENV_DIR" ]; then
  if ! mkdir -p "$ENV_DIR"; then
    echo "::error::Unable to create env directory $ENV_DIR" >&2
    echo "Hint: ensure the SSH user owns the parent directory or pick a user-writable location." >&2
    exit 1
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: run 'chown -R $CURRENT_USER $ENV_DIR' on the host or choose a user-owned path." >&2
  exit 1
fi

ENV_FILE="${REMOTE_ENV_FILE:-${ENV_DIR}/.env}"

echo "📄 Using env file: $ENV_FILE"

ENV_PARENT="$(dirname "$ENV_FILE")"
if [ ! -d "$ENV_PARENT" ]; then
  if ! mkdir -p "$ENV_PARENT"; then
    echo "::error::Unable to create env parent directory $ENV_PARENT" >&2
    exit 1
  fi
fi
if [ ! -w "$ENV_PARENT" ]; then
  echo "::error::Env parent directory $ENV_PARENT is not writable by $CURRENT_USER" >&2
  echo "Hint: adjust permissions or set ENV_FILE_PATH_BASE to a user-owned path." >&2
  exit 1
fi

# --- Helper: run_podman as current user ---------------------------------------------
run_podman() {
  podman "$@"
}

# --- Inspect existing container for port reuse --------------------------------------
EXISTING=false
if run_podman container exists "$CONTAINER_NAME" >/dev/null 2>&1; then
  EXISTING=true
fi

# --- Compute ports ------------------------------------------------------------------
# Prefer provided inputs; otherwise reuse from existing container; otherwise defaults

# Container port resolution (labels for Traefik or env fallbacks)
CONTAINER_PORT="$CONTAINER_PORT_IN"
if [[ -z "$CONTAINER_PORT" ]]; then
  if [[ "$TRAEFIK_ENABLED" == "true" && -n "$ROUTER_NAME" && "$EXISTING" == "true" ]]; then
    OLD_LABEL=$(run_podman inspect -f '{{ index .Config.Labels "traefik.http.services.'"$ROUTER_NAME"'.loadbalancer.server.port" }}' "$CONTAINER_NAME" 2>/dev/null || true)
    if [[ -n "$OLD_LABEL" ]]; then
      CONTAINER_PORT="$OLD_LABEL"
    fi
  fi
  if [[ -z "$CONTAINER_PORT" ]]; then
    CONTAINER_PORT="${WEB_CONTAINER_PORT:-${TARGET_PORT:-${PORT:-8080}}}"
  fi
fi

# Host port resolution (reuse prior mapping; final default 8080)
HOST_PORT="$HOST_PORT_IN"
if [[ -z "$HOST_PORT" && "$EXISTING" == "true" ]]; then
  OLD_PORT_LINE=$(run_podman port "$CONTAINER_NAME" "${CONTAINER_PORT}/tcp" 2>/dev/null || true)
  if [[ -n "$OLD_PORT_LINE" ]]; then
    HOST_PORT="$(echo "$OLD_PORT_LINE" | sed -E 's/.*:([0-9]+)$/\1/')"
  fi
fi
if [[ -z "$HOST_PORT" ]]; then
  HOST_PORT="${WEB_HOST_PORT:-${PORT:-8080}}"
fi

echo "🌐 Service target port (container): $CONTAINER_PORT"

# --- Prepare run args ---------------------------------------------------------------
IMAGE_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PORT_ARGS=()
LABEL_ARGS=()

DOMAIN="$DOMAIN_INPUT"
if [[ -z "$DOMAIN" ]]; then DOMAIN="$DOMAIN_DEFAULT"; fi

if [[ "$TRAEFIK_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  echo "🔀 Traefik mode enabled for domain: $DOMAIN (router: $ROUTER_NAME)"
  if [[ -n "$HOST_PORT_IN" ]]; then
    echo "::notice::Host port publishing is disabled while Traefik is enabled; ignoring host_port inputs."
  fi
  echo "🔖 Traefik labels will advertise container port $CONTAINER_PORT"
  LABEL_ARGS+=(--label "traefik.enable=true")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.rule=Host(\`$DOMAIN\`)")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.entrypoints=websecure")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.tls.certresolver=letsencrypt")
  LABEL_ARGS+=(--label "traefik.http.services.${ROUTER_NAME}.loadbalancer.server.port=${CONTAINER_PORT}")
else
  if [[ -z "$HOST_PORT" || -z "$CONTAINER_PORT" ]]; then
    echo '::error::Host port and container port must both resolve for non-Traefik deployment' >&2
    echo "Hint: Provide host_port/container_port inputs or set WEB_HOST_PORT/WEB_CONTAINER_PORT (or PORT) in the env file." >&2
    exit 1
  fi
  if ! [[ "$HOST_PORT" =~ ^[0-9]+$ && "$CONTAINER_PORT" =~ ^[0-9]+$ ]]; then
    echo '::error::Host/container ports must be numeric values (e.g., 8080).' >&2
    echo "Received host_port='${HOST_PORT}' container_port='${CONTAINER_PORT}'." >&2
    echo "Hint: Strip protocol prefixes or named ports; only raw integers are allowed." >&2
    exit 1
  fi
  echo "🔓 Publishing port mapping host:$HOST_PORT -> container:$CONTAINER_PORT"
  PORT_ARGS=(-p "${HOST_PORT}:${CONTAINER_PORT}")
fi

# --- Login and pull (optional login, always pull) -----------------------------------
if [[ "${REGISTRY_LOGIN:-true}" == "true" ]]; then
  echo "🔐 Logging into registry (if credentials provided) ..."
  if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_TOKEN:-}" ]]; then
    printf '%s' "$REGISTRY_TOKEN" | podman login "$IMAGE_REGISTRY" -u "$REGISTRY_USERNAME" --password-stdin
  else
    echo "ℹ️  No explicit credentials provided; skipping login"
  fi
fi
echo "📥 Pulling image: $IMAGE_REF"
podman pull "$IMAGE_REF"

# --- Stop/replace container ---------------------------------------------------------
echo "🛑 Stopping existing container (if any): $CONTAINER_NAME"
podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing existing container (if any): $CONTAINER_NAME"
podman rm   "$CONTAINER_NAME" >/dev/null 2>&1 || true

# --- Run container -----------------------------------------------------------------
echo "🚀 Starting container: $CONTAINER_NAME"
podman run -d --name "$CONTAINER_NAME" --env-file "$ENV_FILE" \
  "${PORT_ARGS[@]}" \
  --restart="$RESTART_POLICY" \
  --memory="$MEMORY_LIMIT" --memory-swap="$MEMORY_LIMIT" \
  ${EXTRA_RUN_ARGS:+$EXTRA_RUN_ARGS} \
  "${LABEL_ARGS[@]}" \
  "$IMAGE_REF"

# --- Post status --------------------------------------------------------------------
echo " Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}	{{.Status}}	{{.Image}}	{{.Names}}	{{.Ports}}'
