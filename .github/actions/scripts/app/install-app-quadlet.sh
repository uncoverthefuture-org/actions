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

{
  echo "[Unit]"
  echo "Description=${APP_SLUG} (${ENV_NAME}) container (managed by uactions)"
  echo "After=network-online.target"
  echo
  echo "[Container]"
  echo "Image=${IMAGE_REF}"
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
    echo "Memory=${MEMORY_LIMIT}"
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

  echo
  echo "[Install]"
  echo "WantedBy=default.target"
} >"${UNIT_PATH}"

echo "Quadlet unit written to ${UNIT_PATH}" >&2

if command -v systemctl >/dev/null 2>&1; then
  if systemctl --user daemon-reload >/dev/null 2>&1; then
    echo "systemd --user daemon-reload completed" >&2
  else
    echo "::warning::systemctl --user daemon-reload failed; Quadlet changes may not be active until next reload" >&2
  fi
  if systemctl --user enable "${UNIT_NAME}.container" >/dev/null 2>&1; then
    echo "Enabled ${UNIT_NAME}.container for user" >&2
  else
    echo "::warning::Failed to enable ${UNIT_NAME}.container; ensure linger is enabled and try manually" >&2
  fi
else
  echo "::warning::systemctl not found; Quadlet unit created but not registered" >&2
fi
