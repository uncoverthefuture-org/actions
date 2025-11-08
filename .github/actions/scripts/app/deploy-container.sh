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
if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "👤 Remote user: ${CURRENT_USER} (uid:${CURRENT_UID})"
  echo "👥 Groups: ${CURRENT_GROUPS}"
  echo "🔑 sudo: ${SUDO_STATUS}"
fi

echo "  • App:        $APP_SLUG"
echo "  • Env:        $ENV_NAME"
echo "  • Image:      ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# --- Compute names and paths --------------------------------------------------------
CONTAINER_NAME="$CONTAINER_NAME_IN"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="${APP_SLUG}-${ENV_NAME}"
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "📛 Container name: $CONTAINER_NAME"
fi

# Resolve environment directory on the REMOTE host
# Prefer normalized path exported by run-deployment.sh; otherwise compute and normalize
ENV_DIR="${REMOTE_ENV_DIR:-}"
if [[ -z "$ENV_DIR" ]]; then
  # Normalize base path: expand ~ to $HOME and rebase /home/runner -> $HOME
  ENV_BASE_IN="${ENV_FILE_PATH_BASE:-${HOME}/deployments}"
  case "$ENV_BASE_IN" in
    "~/"*) ENV_ROOT="$HOME/${ENV_BASE_IN#~/}" ;;
    "/home/runner/"*) ENV_ROOT="$HOME/${ENV_BASE_IN#/home/runner/}" ;;
    *) ENV_ROOT="$ENV_BASE_IN" ;;
  esac
  ENV_DIR="${ENV_ROOT%/}/${ENV_NAME}/${APP_SLUG}"
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "📁 Preparing environment directory"
fi
# Attempt to ensure directory exists; fallback to sudo mkdir + chown when needed
if [ -d "$ENV_DIR" ] && [ ! -w "$ENV_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
if [ ! -d "$ENV_DIR" ]; then
  if ! mkdir -p "$ENV_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo mkdir -p "$ENV_DIR" 2>/dev/null || true
      sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
    else
      echo "::error::Unable to create env directory $ENV_DIR" >&2
      echo "Hint: ensure the SSH user owns the parent directory or pick a user-writable location." >&2
      exit 1
    fi
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_DIR" 2>/dev/null || true
  fi
fi
if [ ! -w "$ENV_DIR" ]; then
  echo "::error::Environment directory $ENV_DIR is not writable by $CURRENT_USER" >&2
  echo "Hint: run 'chown -R $CURRENT_USER $ENV_DIR' on the host or choose a user-owned path." >&2
  exit 1
fi

ENV_FILE="${REMOTE_ENV_FILE:-${ENV_DIR}/.env}"

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "📄 Using env file"
fi

ENV_PARENT="$(dirname "$ENV_FILE")"
if [ ! -d "$ENV_PARENT" ]; then
  # Ensure parent directory; if blocked, fallback to sudo mkdir + chown
  if ! mkdir -p "$ENV_PARENT" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo mkdir -p "$ENV_PARENT" 2>/dev/null || true
      sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_PARENT" 2>/dev/null || true
    else
      echo "::error::Unable to create env parent directory $ENV_PARENT" >&2
      exit 1
    fi
  fi
fi
if [ ! -w "$ENV_PARENT" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chown -R "$CURRENT_USER:$(id -gn)" "$ENV_PARENT" 2>/dev/null || true
  fi
fi
if [ ! -w "$ENV_PARENT" ]; then
  echo "::warning::Env parent directory is not writable by $CURRENT_USER" >&2
  echo "Hint: adjust permissions or set ENV_FILE_PATH_BASE to a user-owned path." >&2
  exit 1
fi

HOST_PORT_FILE="${ENV_DIR}/.host-port"
AUTO_HOST_PORT_ASSIGNED=false

validate_port_number() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( port < 1 || port > 65535 )); then
    return 1
  fi
  return 0
}

port_in_use() {
  local port="$1"
  if ! validate_port_number "$port"; then
    return 1
  fi
  if command -v ss >/dev/null 2>&1; then
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -q -E "(:|^)$port$"; then
      return 0
    fi
  fi
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
  fi
  if command -v netstat >/dev/null 2>&1; then
    if netstat -tln 2>/dev/null | awk '{print $4}' | grep -q -E "(:|^)$port$"; then
      return 0
    fi
  fi
  return 1
}

find_available_port() {
  local start="$1"
  local limit="${2:-100}"
  local port="$start"
  local attempts=0
  while (( port <= 65535 && attempts <= limit )); do
    if port_in_use "$port"; then
      port=$(( port + 1 ))
      attempts=$(( attempts + 1 ))
      continue
    fi
    echo "$port"
    return 0
  done
  return 1
}

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

if ! validate_port_number "$CONTAINER_PORT"; then
  echo "::error::Invalid container port '$CONTAINER_PORT'. Expected integer between 1-65535." >&2
  exit 1
fi

# Host port resolution (reuse prior mapping; persisted fallback; final default 8080)
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
    echo "ℹ️  Host port $HOST_PORT currently in use by existing container; will reuse after replacement."
  else
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
  echo "💾 Persisted host port assignment"
fi

if [[ "${DEBUG:-false}" == "true" ]]; then
  echo "🌐 Service target port (container): $CONTAINER_PORT"
  echo "🌐 Host port candidate: $HOST_PORT (source: ${HOST_PORT_SOURCE:-manual})"
fi

# --- Prepare run args ---------------------------------------------------------------
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
    LABEL_ARGS+=(--label "traefik.enable=true")

    # Build Host() list with optional aliases and www
    HOSTS=("$DOMAIN")
    if [[ -n "${DOMAIN_ALIASES:-}" ]]; then
      # commas to spaces
      read -r -a _aliases <<< "$(echo "${DOMAIN_ALIASES}" | tr ',' ' ')"
      for a in "${_aliases[@]}"; do
        [[ -z "$a" ]] && continue
        HOSTS+=("$a")
      done
    fi
    case "${INCLUDE_WWW_ALIAS,,}" in
      1|y|yes|true)
        HOSTS+=("www.${DOMAIN}")
        ;;
    esac
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

if [[ "$TRAEFIK_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔒 Skipping host port publish (Traefik handles ingress on 80/443)"
  fi
  PORT_ARGS=()
else
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔓 Publishing port mapping"
  fi
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
NETWORK_ARGS=()
if [[ "$TRAEFIK_ENABLED" == "true" && -n "$TRAEFIK_NETWORK_NAME" ]]; then
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

podman run -d --name "$CONTAINER_NAME" --env-file "$ENV_FILE" \
  "${PORT_ARGS[@]}" \
  --restart="$RESTART_POLICY" \
  --memory="$MEMORY_LIMIT" --memory-swap="$MEMORY_LIMIT" \
  "${DNS_ARGS[@]}" \
  "${NETWORK_ARGS[@]}" \
  ${EXTRA_RUN_ARGS:+$EXTRA_RUN_ARGS} \
  "${LABEL_ARGS[@]}" \
  "$IMAGE_REF"

# --- Post status --------------------------------------------------------------------
echo " Started container: $CONTAINER_NAME (image: $IMAGE_REF)"
echo ""
podman ps --filter name="$CONTAINER_NAME" --format 'table {{.ID}}	{{.Status}}	{{.Image}}	{{.Names}}	{{.Ports}}'
