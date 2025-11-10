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

echo "🔧 Preparing deploy"
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
# Step 1: honor explicit container port inputs. If absent, try to glean the
# port from an existing Traefik label, otherwise fall back to env defaults.
CONTAINER_PORT="$CONTAINER_PORT_IN"
if [[ -z "$CONTAINER_PORT" ]]; then
  if [[ "$TRAEFIK_ENABLED" == "true" && -n "$ROUTER_NAME" && "$EXISTING" == "true" ]]; then
    # When Traefik is enabled, query existing container labels to maintain
    # stable routing across redeployments.
    OLD_LABEL=$(run_podman inspect -f '{{ index .Config.Labels "traefik.http.services.'"$ROUTER_NAME"'.loadbalancer.server.port" }}' "$CONTAINER_NAME" 2>/dev/null || true)
    if [[ -n "$OLD_LABEL" ]]; then
      CONTAINER_PORT="$OLD_LABEL"
    fi
  fi
  if [[ -z "$CONTAINER_PORT" ]]; then
    CONTAINER_PORT="${WEB_CONTAINER_PORT:-${TARGET_PORT:-${PORT:-8080}}}"
  fi
fi

if ! validate_port_number "$CONTAINER_PORT"; then
  echo "::error::Invalid container port '$CONTAINER_PORT'. Expected integer between 1-65535." >&2
  exit 1
fi

# Host port resolution (reuse prior mapping; persisted fallback; final default 8080)
# Step 2: resolve host port using explicit input, existing container mapping,
# persisted metadata, or defaults. This logic is a good candidate for a
# future util (e.g., util/ports.sh::resolve_host_port) if other scripts need it.
HOST_PORT_SOURCE="input"
HOST_PORT="$HOST_PORT_IN"
OLD_PORT_LINE=""
if [[ -z "$HOST_PORT" ]]; then
  HOST_PORT_SOURCE=""
  if [[ "$EXISTING" == "true" ]]; then
    OLD_PORT_LINE=$(run_podman port "$CONTAINER_NAME" "${CONTAINER_PORT}/tcp" 2>/dev/null || true)
    if [[ -n "$OLD_PORT_LINE" ]]; then
      HOST_PORT="$(echo "$OLD_PORT_LINE" | sed -E 's/.*:([0-9]+)$/\1/')"
      HOST_PORT_SOURCE="existing"
    fi
  fi
fi

if [[ -z "$HOST_PORT" && -f "$HOST_PORT_FILE" ]]; then
  # Reuse a previously stored host port so external routing stays consistent.
  STORED_PORT="$(tr -d ' \t\r\n' < "$HOST_PORT_FILE" 2>/dev/null || true)"
  if [[ -n "$STORED_PORT" ]] && validate_port_number "$STORED_PORT"; then
    HOST_PORT="$STORED_PORT"
    HOST_PORT_SOURCE="file"
  elif [[ -n "$STORED_PORT" ]]; then
    echo "::warning::Ignoring stored host port '$STORED_PORT' in $HOST_PORT_FILE (invalid)." >&2
  fi
fi

if [[ -z "$HOST_PORT" ]]; then
  HOST_PORT="${WEB_HOST_PORT:-${PORT:-8080}}"
  HOST_PORT_SOURCE="default"
fi

if [[ -z "$HOST_PORT" ]]; then
  echo "::error::Failed to resolve host port" >&2
  exit 1
fi

if ! validate_port_number "$HOST_PORT"; then
  echo "::warning::Host port '$HOST_PORT' is invalid; defaulting to 8080." >&2
  HOST_PORT=8080
  HOST_PORT_SOURCE="default"
fi

EXISTING_PORT=""
if [[ -n "$OLD_PORT_LINE" ]]; then
  EXISTING_PORT_COUNT=$(printf '%s\n' "$OLD_PORT_LINE" | wc -l | tr -d ' ')
  if [[ "$EXISTING_PORT_COUNT" == "1" ]]; then
    EXISTING_PORT="$(printf '%s\n' "$OLD_PORT_LINE" | sed -E 's/.*:([0-9]+)$/\1/')"
  else
    echo "::warning::Multiple host ports found for ${CONTAINER_NAME}:${CONTAINER_PORT}/tcp; unable to auto-reuse." >&2
    EXISTING_PORT=""
  fi
fi

if port_in_use "$HOST_PORT"; then
  if [[ "$EXISTING" == "true" && "$EXISTING_PORT" = "$HOST_PORT" ]]; then
    # Existing running container occupies the port; keep it so replacement is seamless.
    echo "ℹ️  Host port $HOST_PORT currently in use by existing container; will reuse after replacement."
  else
    # Host port collision scenario—search for the next free port using util helper.
    echo "⚠️  Host port $HOST_PORT is already in use; searching for the next available port." >&2
    NEW_PORT="$(find_available_port "$HOST_PORT" 500)" || true
    if [[ -z "$NEW_PORT" ]]; then
      echo "::error::Unable to find an available port starting from $HOST_PORT" >&2
      exit 1
    fi
    echo "🔁 Auto-selected host port $NEW_PORT"
    HOST_PORT="$NEW_PORT"
    HOST_PORT_SOURCE="auto"
  fi
fi

if [[ "$HOST_PORT_SOURCE" != "input" ]]; then
  AUTO_HOST_PORT_ASSIGNED=true
fi

if ! printf '%s\n' "$HOST_PORT" > "$HOST_PORT_FILE"; then
  echo "::warning::Failed to persist host port to $HOST_PORT_FILE" >&2
fi

if [[ "$AUTO_HOST_PORT_ASSIGNED" == "true" && "${DEBUG:-false}" == "true" ]]; then
  # Document auto-selection to assist with future troubleshooting.
  echo "💾 Persisted host port assignment"
fi

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
    # Fallback path: script unavailable, so synthesize labels inline. Consider
    # extracting this branch to a shared helper if other actions need the same fallback.
    LABEL_ARGS+=(--label "traefik.enable=true")
    
    # Build Host() list with precedence:
    # 1) DOMAIN_HOSTS (explicit, CSV/space-separated)
    # 2) DOMAIN + DOMAIN_ALIASES (+ www.<apex> only when DOMAIN is apex)
    HOSTS=()
    if [[ -n "${DOMAIN_HOSTS:-}" ]]; then
      # Use explicit list as-is when provided (overrides aliases/www behavior)
      read -r -a HOSTS <<< "$(echo "${DOMAIN_HOSTS}" | tr ',' ' ')"
    else
      HOSTS+=("$DOMAIN")
      if [[ -n "${DOMAIN_ALIASES:-}" ]]; then
        # commas to spaces
        read -r -a _aliases <<< "$(echo "${DOMAIN_ALIASES}" | tr ',' ' ')"
        for a in "${_aliases[@]}"; do
          [[ -z "$a" ]] && continue
          HOSTS+=("$a")
        done
      fi
      # Only include www.<apex> when DOMAIN itself is apex (no subdomain)
      case "${INCLUDE_WWW_ALIAS,,}" in
        1|y|yes|true)
          dom_lower="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
          IFS='.' read -r -a parts <<< "$dom_lower"
          count=${#parts[@]}
          if (( count >= 2 )); then
            apex="${parts[count-2]}.${parts[count-1]}"
            if [[ "$dom_lower" = "$apex" ]]; then
              HOSTS+=("www.${apex}")
            fi
          fi
          ;;
      esac
    fi
    # De-duplicate
    UNIQ_HOSTS=()
    seen=""
    for h in "${HOSTS[@]}"; do
      [[ -z "$h" ]] && continue
      if [[ ",${seen}," != *",${h},"* ]]; then
        UNIQ_HOSTS+=("$h")
        seen+="${seen:+,}${h}"
      fi
    done
    echo "🧭 Hosts configured: ${UNIQ_HOSTS[*]}"
    # Compose Host(`a`) || Host(`b`) for Traefik v3
    HOST_RULE_EXPR=""
    for idx in "${!UNIQ_HOSTS[@]}"; do
      d="${UNIQ_HOSTS[$idx]}"
      if [[ $idx -gt 0 ]]; then HOST_RULE_EXPR+=" || "; fi
      HOST_RULE_EXPR+="Host(\"${d}\")"
    done
    printf -v ROUTER_RULE_LABEL 'traefik.http.routers.%s.rule=%s' "$ROUTER_NAME" "$HOST_RULE_EXPR"
    LABEL_ARGS+=(--label "$ROUTER_RULE_LABEL")
    printf -v ROUTER_SERVICE_LABEL 'traefik.http.routers.%s.service=%s' "$ROUTER_NAME" "$ROUTER_NAME"
    LABEL_ARGS+=(--label "$ROUTER_SERVICE_LABEL")
    TRAEFIK_ENABLE_ACME_EFF="${TRAEFIK_ENABLE_ACME:-true}"
    if [[ "$TRAEFIK_ENABLE_ACME_EFF" == "true" ]]; then
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.entrypoints=websecure")
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.tls=true")
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.tls.certresolver=letsencrypt")
    else
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}.entrypoints=web")
    fi
    printf -v SERVICE_PORT_LABEL 'traefik.http.services.%s.loadbalancer.server.port=%s' "$ROUTER_NAME" "$CONTAINER_PORT"
    LABEL_ARGS+=(--label "$SERVICE_PORT_LABEL")
    if [[ -n "$TRAEFIK_NETWORK_NAME" ]]; then
      LABEL_ARGS+=(--label "traefik.docker.network=${TRAEFIK_NETWORK_NAME}")
    fi

    if [[ "$TRAEFIK_ENABLE_ACME_EFF" == "true" ]]; then
      printf -v ROUTER_HTTP_RULE_LABEL 'traefik.http.routers.%s-http.rule=%s' "$ROUTER_NAME" "$HOST_RULE_EXPR"
      LABEL_ARGS+=(--label "$ROUTER_HTTP_RULE_LABEL")
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}-http.entrypoints=web")
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}-http.service=${ROUTER_NAME}")
      LABEL_ARGS+=(--label "traefik.http.middlewares.${ROUTER_NAME}-https-redirect.redirectscheme.scheme=https")
      LABEL_ARGS+=(--label "traefik.http.routers.${ROUTER_NAME}-http.middlewares=${ROUTER_NAME}-https-redirect")
    fi
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
  # Guarantee the Traefik network exists, creating it on first deploy. Could be
  # elevated into util/network.sh if additional scripts require shared logic.
  if ! podman network exists "$TRAEFIK_NETWORK_NAME" >/dev/null 2>&1; then
    if [[ "${DEBUG:-false}" == "true" ]]; then echo "🌐 Creating Traefik network $TRAEFIK_NETWORK_NAME"; fi
    podman network create "$TRAEFIK_NETWORK_NAME"
  fi
  NETWORK_ARGS+=(--network "$TRAEFIK_NETWORK_NAME")
fi

# --- DNS/Resolver handling --------------------------------------------------------
# Prefer mounting the host's real resolv.conf (systemd-resolved) so the container
# inherits accurate nameservers. If not readable/present, fallback to public DNS.
# Example:
#   - Mount: -v /run/systemd/resolve/resolv.conf:/etc/resolv.conf:ro
#   - Fallback: --dns 1.1.1.1 --dns 8.8.8.8
DNS_ARGS=()
RESOLV_SRC="/run/systemd/resolve/resolv.conf"
if [ -r "$RESOLV_SRC" ] && [ -s "$RESOLV_SRC" ]; then
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🧭 DNS: mounting host resolv.conf from $RESOLV_SRC"
  fi
  DNS_ARGS+=( -v "$RESOLV_SRC:/etc/resolv.conf:ro" )
else
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🧭 DNS: using public resolvers (1.1.1.1, 8.8.8.8)"
  fi
  DNS_ARGS+=( --dns 1.1.1.1 --dns 8.8.8.8 )
fi


# Bring everything together: build the full podman invocation so we can emit a
# preview (when DEBUG=true) before running it for real.
podman_run_cmd=(podman run -d --name "$CONTAINER_NAME" --env-file "$ENV_FILE")
podman_run_cmd+=("${PORT_ARGS[@]}")
podman_run_cmd+=(--restart="$RESTART_POLICY" --memory="$MEMORY_LIMIT" --memory-swap="$MEMORY_LIMIT")
podman_run_cmd+=("${DNS_ARGS[@]}")
podman_run_cmd+=("${NETWORK_ARGS[@]}")
if [[ -n "${EXTRA_RUN_ARGS:-}" ]]; then
  # Mimic original behaviour: allow callers to supply a whitespace-separated
  # string of extra podman arguments (e.g., "--add-host foo:127.0.0.1").
  # shellcheck disable=SC2206
  EXTRA_RUN_ARGS_ARRAY=($EXTRA_RUN_ARGS)
  podman_run_cmd+=("${EXTRA_RUN_ARGS_ARRAY[@]}")
fi
podman_run_cmd+=("${LABEL_ARGS[@]}")
podman_run_cmd+=("$IMAGE_REF")

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "🐚 podman run command (preview):"
  printf '  '
  printf '%q ' "${podman_run_cmd[@]}"
  printf '\n'
fi

"${podman_run_cmd[@]}"

# --- Post status --------------------------------------------------------------------
# Provide immediate feedback showing the container status table so operators can
# verify the deployment succeeded without inspecting the remote host manually.
echo " Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}\t{{.Status}}\t{{.Image}}\t{{.Names}}\t{{.Ports}}'
