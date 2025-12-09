#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install-app-quadlet.sh
# ----------------------------------------------------------------------------
# Purpose:
#   Generate or update a Podman Quadlet .container unit for an application
#   container so that it can be managed by systemd --user and restarted
#   automatically after reboots. This script is intended to be invoked from
#   deploy-container.sh / run-deployment.sh *after* a successful podman run
#   so that the Quadlet definition reflects the last deployed configuration.
#
# Inputs (environment variables):
#   APP_SLUG           - Application slug (used in unit naming)
#   ENV_NAME           - Environment name (production|staging|development)
#   CONTAINER_NAME     - Effective container name
#   IMAGE_REF          - Fully-qualified image reference (registry/name:tag)
#   REMOTE_ENV_FILE    - Path to the .env file on the host (if any)
#   TRAEFIK_ENABLED    - 'true' when Traefik routing is enabled
#   TRAEFIK_NETWORK_NAME - Network name for Traefik/app containers
#   HOST_PORT          - Host port when Traefik is disabled
#   CONTAINER_PORT     - Container service port
#   DEPLOY_DIR_SOURCE  - Host path for deployment directory (if mounted)
#   DEPLOY_DIR_CONTAINER_PATH - Container path for deployment directory
#   MEMORY_LIMIT       - Memory limit (e.g. 512m)
#   CPU_LIMIT          - CPU limit (e.g. 0.5)
#   QUADLET_ENABLED    - 'true' (default) to write Quadlet unit, 'false' to skip
#
# Traefik routing inputs (CRITICAL for post-reboot discovery):
#   ROUTER_NAME        - Traefik router/service name slug (e.g. app-production)
#   DOMAIN             - Effective domain for Host() rule (e.g. app.example.com)
#   TRAEFIK_ENABLE_ACME - 'true' to include TLS/certresolver labels
#   DOMAIN_HOSTS       - Explicit comma-separated host list (overrides DOMAIN)
#   DOMAIN_ALIASES     - Additional comma-separated domain aliases
#   INCLUDE_WWW_ALIAS  - 'true' to include www.<apex> in Host() rule
#
# Behavior:
#   - When QUADLET_ENABLED != 'false', writes
#       $HOME/.config/containers/systemd/<app>-<env>.container
#   - Uses [Container] keys like Image=, ContainerName=, EnvironmentFile=,
#     Network=, PublishPort=, Volume=, Memory= to mirror the last deploy.
#   - Runs `systemctl --user daemon-reload` and `systemctl --user enable` so
#     the unit starts on user session/reboot (assuming linger is enabled).
#
# Example:
#   APP_SLUG=myapp ENV_NAME=production CONTAINER_NAME=myapp-production \
#   IMAGE_REF=ghcr.io/org/myapp:1.2.3 REMOTE_ENV_FILE=/home/app/deploy/.env \
#   HOST_PORT=8080 CONTAINER_PORT=3000 MEMORY_LIMIT=512m CPU_LIMIT=0.5 \
#   ./install-app-quadlet.sh
#
#   This will create ~/.config/containers/systemd/myapp-production.container
#   and enable the corresponding myapp-production.service.
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../util/podman.sh
source "${SCRIPT_DIR}/../util/podman.sh"

QUADLET_ENABLED="${QUADLET_ENABLED:-true}"
if [[ "${QUADLET_ENABLED}" != "true" ]]; then
  echo "::notice::Quadlet persistence disabled via QUADLET_ENABLED=${QUADLET_ENABLED}; skipping .container generation" >&2
  exit 0
fi

APP_SLUG="${APP_SLUG:-}"
ENV_NAME="${ENV_NAME:-}"
CONTAINER_NAME="${CONTAINER_NAME:-}"
IMAGE_REF="${IMAGE_REF:-}"

if [[ -z "${APP_SLUG}" || -z "${ENV_NAME}" || -z "${CONTAINER_NAME}" || -z "${IMAGE_REF}" ]]; then
  echo "::warning::install-app-quadlet.sh missing required inputs; skipping Quadlet unit" >&2
  echo "  APP_SLUG='${APP_SLUG}'" >&2
  echo "  ENV_NAME='${ENV_NAME}'" >&2
  echo "  CONTAINER_NAME='${CONTAINER_NAME}'" >&2
  echo "  IMAGE_REF='${IMAGE_REF}'" >&2
  exit 0
fi

UNIT_NAME="${APP_SLUG}-${ENV_NAME}"
QUADLET_DIR="${HOME}/.config/containers/systemd"
mkdir -p "${QUADLET_DIR}"

UNIT_PATH="${QUADLET_DIR}/${UNIT_NAME}.container"

TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-traefik-network}"
HOST_PORT="${HOST_PORT:-}"
CONTAINER_PORT="${CONTAINER_PORT:-}"
DEPLOY_DIR_SOURCE="${DEPLOY_DIR_SOURCE:-}"
DEPLOY_DIR_CONTAINER_PATH="${DEPLOY_DIR_CONTAINER_PATH:-}" 
MEMORY_LIMIT="${MEMORY_LIMIT:-}"
CPU_LIMIT="${CPU_LIMIT:-}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-}"

# Traefik routing variables - CRITICAL for post-reboot container discovery
# Without these labels, Traefik won't know how to route traffic to containers
# restarted by systemd after a reboot, causing 404 errors.
ROUTER_NAME="${ROUTER_NAME:-}"
DOMAIN="${DOMAIN:-}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-true}"
DOMAIN_HOSTS="${DOMAIN_HOSTS:-}"
DOMAIN_ALIASES="${DOMAIN_ALIASES:-}"
INCLUDE_WWW_ALIAS="${INCLUDE_WWW_ALIAS:-false}"

{
  echo "[Unit]"
  echo "Description=${APP_SLUG} (${ENV_NAME}) container (managed by uactions)"
  echo "After=network-online.target"
  echo
  echo "[Container]"
  echo "Image=${IMAGE_REF}"
  # Prevent pulling from registry on restart - use only locally cached images.
  # This is critical because auth tokens are not available after server reboot.
  echo "Pull=never"
  echo "ContainerName=${CONTAINER_NAME}"

  if [[ -n "${REMOTE_ENV_FILE}" ]]; then
    echo "EnvironmentFile=${REMOTE_ENV_FILE}"
  fi

  if [[ "${TRAEFIK_ENABLED}" == "true" && -n "${TRAEFIK_NETWORK_NAME}" ]]; then
    echo "Network=${TRAEFIK_NETWORK_NAME}"
  elif [[ -n "${TRAEFIK_NETWORK_NAME}" ]]; then
    echo "Network=${TRAEFIK_NETWORK_NAME}"
  fi

  if [[ "${TRAEFIK_ENABLED}" != "true" && -n "${HOST_PORT}" && -n "${CONTAINER_PORT}" ]]; then
    echo "PublishPort=${HOST_PORT}:${CONTAINER_PORT}"
  fi

  if [[ -n "${DEPLOY_DIR_SOURCE}" && -n "${DEPLOY_DIR_CONTAINER_PATH}" ]]; then
    echo "Volume=${DEPLOY_DIR_SOURCE}:${DEPLOY_DIR_CONTAINER_PATH}"
  fi

  if [[ -n "${MEMORY_LIMIT}" ]]; then
    echo "PodmanArgs=--memory=${MEMORY_LIMIT} --memory-swap=${MEMORY_LIMIT}"
  fi

  # When CPU_LIMIT is set we prefer to mirror the runtime --cpus behavior in the
  # Quadlet unit so systemd restarts use the same resource profile. However,
  # some hosts (for example, rootless on cgroups v1) do not expose a "cpu"
  # cgroup controller, in which case Podman will reject --cpus. To avoid
  # Quadlet-based restarts failing with the same error that the deploy script
  # guards against, only emit PodmanArgs when the helper confirms cpu support.
  # Example: CPU_LIMIT=0.5 on a host with cpu cgroup available writes
  #   PodmanArgs=--cpus=0.5
  # while the same setting on a host without cpu controller will print a
  # warning and omit PodmanArgs so the container still restarts.
  if [[ -n "${CPU_LIMIT}" ]]; then
    if podman_cpu_cgroup_available; then
      echo "PodmanArgs=--cpus=${CPU_LIMIT}"
    else
      echo "::warning::CPU_LIMIT='${CPU_LIMIT}' configured but Podman host does not expose a 'cpu' cgroup controller; skipping PodmanArgs=--cpus in Quadlet unit (container will restart without a CPU limit)." >&2
    fi
  fi

  echo "Label=app=${APP_SLUG}"
  echo "Label=env=${ENV_NAME}"
  echo "Label=managed-by=uactions"

  # =========================================================================
  # TRAEFIK LABELS - CRITICAL for post-reboot container discovery
  # =========================================================================
  # When TRAEFIK_ENABLED=true and DOMAIN is set, we must include the same
  # Traefik labels that were applied during the initial deployment. Without
  # these labels, Traefik's Docker provider won't discover the container after
  # a reboot and requests will return 404 errors.
  #
  # Example generated labels:
  #   Label=traefik.enable=true
  #   Label=traefik.http.routers.myapp-prod.rule=Host("app.example.com")
  #   Label=traefik.http.routers.myapp-prod.service=myapp-prod
  #   Label=traefik.http.services.myapp-prod.loadbalancer.server.port=3000
  # =========================================================================
  if [[ "${TRAEFIK_ENABLED}" == "true" && -n "${DOMAIN}" && -n "${ROUTER_NAME}" && -n "${CONTAINER_PORT}" ]]; then
    # Build host list for Traefik rule
    # Precedence: explicit DOMAIN_HOSTS > DOMAIN + DOMAIN_ALIASES + www variant
    declare -a _hosts=()
    if [[ -n "${DOMAIN_HOSTS}" ]]; then
      IFS=',' read -r -a _hosts <<< "$(echo "${DOMAIN_HOSTS}" | tr ' ' ',')"
    else
      _hosts+=("${DOMAIN}")
      if [[ -n "${DOMAIN_ALIASES}" ]]; then
        IFS=',' read -r -a _aliases <<< "$(echo "${DOMAIN_ALIASES}" | tr ' ' ',')"
        for _alias in "${_aliases[@]}"; do
          [[ -z "$_alias" ]] && continue
          _hosts+=("$_alias")
        done
      fi
      # Include www.<apex> when INCLUDE_WWW_ALIAS=true and domain is apex
      if [[ "${INCLUDE_WWW_ALIAS,,}" == "true" ]]; then
        _dom_lower="$(printf '%s' "${DOMAIN}" | tr '[:upper:]' '[:lower:]')"
        IFS='.' read -r -a _parts <<< "$_dom_lower"
        _count=${#_parts[@]}
        if (( _count >= 2 )); then
          _apex="${_parts[_count-2]}.${_parts[_count-1]}"
          if [[ "$_dom_lower" = "$_apex" ]]; then
            _hosts+=("www.${_apex}")
          fi
        fi
      fi
      # When domain starts with www., also include the apex
      _dom_lower="$(printf '%s' "${DOMAIN}" | tr '[:upper:]' '[:lower:]')"
      if [[ "$_dom_lower" == www.* ]]; then
        _apex_candidate="${_dom_lower#www.}"
        [[ -n "$_apex_candidate" ]] && _hosts+=("$_apex_candidate")
      fi
    fi

    # De-duplicate hosts while preserving order
    declare -a _uniq_hosts=()
    _seen=""
    for _h in "${_hosts[@]}"; do
      [[ -z "$_h" ]] && continue
      if [[ ",${_seen}," != *",${_h},"* ]]; then
        _uniq_hosts+=("$_h")
        _seen+="${_seen:+,}${_h}"
      fi
    done

    # Build Host("a") || Host("b") expression
    _host_rule=""
    for _idx in "${!_uniq_hosts[@]}"; do
      _hval="${_uniq_hosts[$_idx]}"
      if [[ $_idx -gt 0 ]]; then _host_rule+=" || "; fi
      _host_rule+="Host(\"${_hval}\")"
    done

    # Emit the fundamental traefik.enable label - without this, Traefik ignores the container
    echo "Label=traefik.enable=true"

    # Router configuration
    echo "Label=traefik.http.routers.${ROUTER_NAME}.rule=${_host_rule}"
    echo "Label=traefik.http.routers.${ROUTER_NAME}.service=${ROUTER_NAME}"

    # Service port configuration
    echo "Label=traefik.http.services.${ROUTER_NAME}.loadbalancer.server.port=${CONTAINER_PORT}"

    # TLS configuration when ACME is enabled
    if [[ "${TRAEFIK_ENABLE_ACME,,}" == "true" ]]; then
      echo "Label=traefik.http.routers.${ROUTER_NAME}.entrypoints=websecure"
      echo "Label=traefik.http.routers.${ROUTER_NAME}.tls=true"
      echo "Label=traefik.http.routers.${ROUTER_NAME}.tls.certresolver=letsencrypt"

      # HTTP to HTTPS redirect router
      echo "Label=traefik.http.routers.${ROUTER_NAME}-http.rule=${_host_rule}"
      echo "Label=traefik.http.routers.${ROUTER_NAME}-http.entrypoints=web"
      echo "Label=traefik.http.routers.${ROUTER_NAME}-http.service=${ROUTER_NAME}"
      echo "Label=traefik.http.middlewares.${ROUTER_NAME}-https-redirect.redirectscheme.scheme=https"
      echo "Label=traefik.http.routers.${ROUTER_NAME}-http.middlewares=${ROUTER_NAME}-https-redirect"
    else
      echo "Label=traefik.http.routers.${ROUTER_NAME}.entrypoints=web"
    fi

    # Network label for Traefik to find the container on the correct network
    if [[ -n "${TRAEFIK_NETWORK_NAME}" ]]; then
      echo "Label=traefik.docker.network=${TRAEFIK_NETWORK_NAME}"
    fi

    echo "::notice::Quadlet unit includes Traefik labels for router '${ROUTER_NAME}' → ${_host_rule}" >&2
  elif [[ "${TRAEFIK_ENABLED}" == "true" ]]; then
    echo "::warning::TRAEFIK_ENABLED=true but missing DOMAIN ('${DOMAIN}'), ROUTER_NAME ('${ROUTER_NAME}'), or CONTAINER_PORT ('${CONTAINER_PORT}'); Quadlet unit will NOT include Traefik labels. Container may return 404 after reboot." >&2
  fi

  echo
  echo "[Install]"
  echo "WantedBy=default.target"
} >"${UNIT_PATH}"

echo "Quadlet unit written to ${UNIT_PATH}" >&2

# Best-effort: ensure user lingering is enabled so user-level systemd can
# restart the Quadlet-managed app container after reboots even when the user
# is not actively logged in. This mirrors the Portainer behavior and keeps the
# persistence model consistent across management UIs and application services.
if command -v loginctl >/dev/null 2>&1; then
  CURRENT_USER_APP="$(id -un)"
  if ! loginctl show-user "${CURRENT_USER_APP}" 2>/dev/null | grep -q "Linger=yes"; then
    loginctl enable-linger "${CURRENT_USER_APP}" >/dev/null 2>&1 || true
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  # Quadlet .container files (for example, myapp-production.container) are
  # consumed by systemd's generators and exposed as standard service units
  # (myapp-production.service). The .service name is what operators should
  # manage via `systemctl --user`.
  APP_SERVICE_NAME="${UNIT_NAME}.service"
  if systemctl --user daemon-reload >/dev/null 2>&1; then
    echo "systemd --user daemon-reload completed" >&2
  else
    echo "::warning::systemctl --user daemon-reload failed; Quadlet changes may not be active until next reload" >&2
  fi
  # For application containers we rely on the [Install] section in the Quadlet
  # unit so the generator treats the service as enabled on future logins/
  # reboots. The initial container has already been started by
  # deploy-container.sh, so we avoid starting it again here to prevent a second
  # podman run race. Operators can start it on-demand via systemctl --user.
  echo "Quadlet service ${APP_SERVICE_NAME} is available; start it with: systemctl --user start ${APP_SERVICE_NAME}" >&2
else
  echo "::warning::systemctl not found; Quadlet unit created but not registered" >&2
fi
