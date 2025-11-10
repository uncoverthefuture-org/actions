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
echo "================================================================"

# --- Compute names and paths --------------------------------------------------------
# Derive final container name: honor explicit input but fall back to
# <app-slug>-<env> when unset so multiple environments coexist predictably.
CONTAINER_NAME="$CONTAINER_NAME_IN"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="${APP_SLUG}-${ENV_NAME}"
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  # Example: DEBUG=true APP_SLUG=demo ENV_NAME=staging prints "demo-staging"
  echo "📛 Container name: $CONTAINER_NAME"
fi

# Environment directory and file are prepared by run-deployment/setup-env-file.
# These exports ensure downstream scripts operate on the same resolved paths.
ENV_DIR="${REMOTE_ENV_DIR:-}"
ENV_FILE="${REMOTE_ENV_FILE:-}"
if [[ -z "$ENV_DIR" || -z "$ENV_FILE" ]]; then
  echo "::error::Deployment environment variables REMOTE_ENV_DIR/REMOTE_ENV_FILE not set." >&2
  echo "Hint: ensure run-deployment.sh invoked setup-env-file before calling deploy-container." >&2
  exit 1
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  # Confirm to operators which directory/file the script will mutate.
  echo "� Using prepared environment directory: $ENV_DIR"
  echo "📄 Using env file: $ENV_FILE"
fi

# Persisted host-port assignments live alongside the env file; track whether
# the script auto-selects a port so we can emit guidance at the end.
HOST_PORT_FILE="${ENV_DIR}/.host-port"
AUTO_HOST_PORT_ASSIGNED=false

# --- Helper: run_podman as current user ---------------------------------------------
# Trim repetition: every podman invocation runs as the SSH user, so centralize
# the call. Candidate for util/podman.sh if reused elsewhere.
run_podman() {
  podman "$@"
}

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

DOMAIN="$DOMAIN_INPUT"
if [[ -z "$DOMAIN" ]]; then DOMAIN="$DOMAIN_DEFAULT"; fi

TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-}"
if [[ "$TRAEFIK_ENABLED" == "true" && -z "$TRAEFIK_NETWORK_NAME" ]]; then
  TRAEFIK_NETWORK_NAME="traefik-network"
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
      INCLUDE_WWW_ALIAS="${INCLUDE_WWW_ALIAS:-false}" \
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
    mapfile -t FALLBACK_LABELS < <(build_traefik_labels_fallback "$ROUTER_NAME" "$DOMAIN" "$CONTAINER_PORT" "${TRAEFIK_ENABLE_ACME_EFF}" "${DOMAIN_HOSTS:-}" "${DOMAIN_ALIASES:-${ALIASES:-}}" "${INCLUDE_WWW_ALIAS:-false}" "${TRAEFIK_NETWORK_NAME:-}")
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
echo "🛑 Stopping existing container (if any): $CONTAINER_NAME"
podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing existing container (if any): $CONTAINER_NAME"
podman rm   "$CONTAINER_NAME" >/dev/null 2>&1 || true

# --- Run container -----------------------------------------------------------------
echo "🚀 Starting container: $CONTAINER_NAME"
NETWORK_ARGS=()
if [[ "$TRAEFIK_ENABLED" == "true" && -n "$TRAEFIK_NETWORK_NAME" ]]; then
  arg=$(ensure_traefik_network "$TRAEFIK_NETWORK_NAME" "${DEBUG:-false}")
  [[ -n "$arg" ]] && NETWORK_ARGS+=($arg)
fi

# --- DNS/Resolver handling --------------------------------------------------------
# Prefer mounting the host's real resolv.conf (systemd-resolved) so the container
# inherits accurate nameservers. If not readable/present, fallback to public DNS.
# Example:
#   - Mount: -v /run/systemd/resolve/resolv.conf:/etc/resolv.conf:ro
#   - Fallback: --dns 1.1.1.1 --dns 8.8.8.8
mapfile -t DNS_ARGS < <(podman_build_dns_args "${DEBUG:-false}")


# Assemble and execute podman run with a DEBUG preview via shared helper.
podman_run_with_preview "$CONTAINER_NAME" "$ENV_FILE" "$RESTART_POLICY" "$MEMORY_LIMIT" "$IMAGE_REF" "${EXTRA_RUN_ARGS:-}" "${DEBUG:-false}" \
  PORT_ARGS[@] DNS_ARGS[@] NETWORK_ARGS[@] LABEL_ARGS[@]

# --- Post status --------------------------------------------------------------------
# Provide immediate feedback showing the container status table so operators can
# verify the deployment succeeded without inspecting the remote host manually.
echo " Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}\t{{.Status}}\t{{.Image}}\t{{.Names}}\t{{.Ports}}'
