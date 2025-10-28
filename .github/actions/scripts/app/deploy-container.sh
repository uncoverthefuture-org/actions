#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# deploy-container.sh
# ----------------------------------------------------------------------------
# Purpose:
#   Run or replace an application container via Podman, with optional Traefik
#   routing. Designed to be called from CI after env file and image are ready.
#
# Inputs (environment variables):
#   PODMAN_USER           - Linux user who should own/run the container (default: deployer)
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
PODMAN_USER="${PODMAN_USER:-deployer}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-}"          # required
IMAGE_TAG="${IMAGE_TAG:-latest}"
APP_SLUG="${APP_SLUG:-}"              # required
ENV_NAME="${ENV_NAME:-}"              # required
CONTAINER_NAME_IN="${CONTAINER_NAME_IN:-}"
ENV_FILE_PATH_BASE="${ENV_FILE_PATH_BASE:-/var/deployments}"
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
ENV_FILE="${REMOTE_ENV_FILE:-${ENV_DIR}/.env}"

echo "📄 Using env file: $ENV_FILE"

# --- Helper: run_podman as PODMAN_USER ---------------------------------------------
run_podman() {
  if [[ "$(id -un)" == "$PODMAN_USER" ]]; then
    podman "$@"
  else
    sudo -H -u "$PODMAN_USER" podman "$@"
  fi
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
    CONTAINER_PORT="${WEB_CONTAINER_PORT:-${TARGET_PORT:-${PORT:-3000}}}"
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

echo "🌐 Service port: container:$CONTAINER_PORT"

# --- Prepare run args ---------------------------------------------------------------
IMAGE_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PORT_ARGS=()
LABEL_ARGS=()

DOMAIN="$DOMAIN_INPUT"
if [[ -z "$DOMAIN" ]]; then DOMAIN="$DOMAIN_DEFAULT"; fi

if [[ "$TRAEFIK_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  echo "🔀 Traefik mode enabled for domain: $DOMAIN (router: $ROUTER_NAME)"
  LABEL_ARGS+=(--label "traefik.enable=true")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.rule=Host(\`$DOMAIN\`)")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.entrypoints=websecure")
  LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.tls.certresolver=letsencrypt")
  LABEL_ARGS+=(--label "traefik.http.services.${ROUTER_NAME}.loadbalancer.server.port=${CONTAINER_PORT}")
else
  echo "🔓 Publishing port mapping host:$HOST_PORT -> container:$CONTAINER_PORT"
  PORT_ARGS=(-p "${HOST_PORT}:${CONTAINER_PORT}")
fi

# --- Login and pull (optional login, always pull) -----------------------------------
if [[ "${REGISTRY_LOGIN:-true}" == "true" ]]; then
  echo "🔐 Logging into registry (if credentials provided) ..."
  if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_TOKEN:-}" ]]; then
    printf '%s' "$REGISTRY_TOKEN" | run_podman login "$IMAGE_REGISTRY" -u "$REGISTRY_USERNAME" --password-stdin
  else
    echo "ℹ️  No explicit credentials provided; skipping login"
  fi
fi
echo "📥 Pulling image: $IMAGE_REF"
run_podman pull "$IMAGE_REF"

# --- Stop/replace container ---------------------------------------------------------
echo "🛑 Stopping existing container (if any): $CONTAINER_NAME"
run_podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing existing container (if any): $CONTAINER_NAME"
run_podman rm   "$CONTAINER_NAME" >/dev/null 2>&1 || true

# --- Run container -----------------------------------------------------------------
echo "🚀 Starting container: $CONTAINER_NAME"
run_podman run -d --name "$CONTAINER_NAME" --env-file "$ENV_FILE" \
  "${PORT_ARGS[@]}" \
  --restart="$RESTART_POLICY" \
  --memory="$MEMORY_LIMIT" --memory-swap="$MEMORY_LIMIT" \
  ${EXTRA_RUN_ARGS:+$EXTRA_RUN_ARGS} \
  "${LABEL_ARGS[@]}" \
  "$IMAGE_REF"

# --- Post status --------------------------------------------------------------------
echo "✅ Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
run_podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}\t{{.Status}}\t{{.Image}}\t{{.Names}}\t{{.Ports}}'
