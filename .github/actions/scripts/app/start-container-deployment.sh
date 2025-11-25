#!/usr/bin/env bash
# start-container-deployment.sh - Thin orchestrator run on the remote host
# Purpose: Keep the GitHub Action SSH step short by delegating to this script.
# Behavior:
# - Assumes $HOME/uactions/scripts has been installed on the remote host
# - Uses already-exported environment variables from the caller
# - Runs run-deployment.sh to perform the container deployment
# - Prints a concise summary and runs a Traefik probe if applicable
set -euo pipefail

if [ "${DEBUG:-false}" = "true" ]; then set -x; fi

SCRIPT_ROOT="$HOME/uactions/scripts"
APP_DIR="$SCRIPT_ROOT/app"
TRAEFIK_DIR="$SCRIPT_ROOT/traefik"

echo "================================================================"
echo "Running deployment script..."
echo "  Script: $APP_DIR/run-deployment.sh"
echo "  App: ${APP_SLUG:-<unknown>}"
if [ -n "${IMAGE_REGISTRY:-}" ] && [ -n "${IMAGE_NAME:-}" ] && [ -n "${IMAGE_TAG:-}" ]; then
  echo "  Image: ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
fi
echo "  Traefik: ${TRAEFIK_ENABLED:-false}"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "📄 Using env file: ${REMOTE_ENV_FILE:-<none>}"
fi
echo "================================================================"

"$APP_DIR/run-deployment.sh"

echo "================================================================"
# Derive effective values for probe
ROUTER="${ROUTER_NAME:-}"
DOMAIN_EFFECTIVE="${DOMAIN_INPUT:-${DOMAIN_DEFAULT:-}}"
SERVICE_PORT="${CONTAINER_PORT_IN:-8080}"
PROBE_PATH="${PROBE_PATH:-/}"

echo "Router: ${ROUTER}"
echo "Domain: ${DOMAIN_EFFECTIVE}"
echo "Service Port: ${SERVICE_PORT}"
echo "Probe Path: ${PROBE_PATH}"
echo "================================================================"

# Probe tuning: enable HTTP fallback and slightly extend timeout for slow DNS/ACME
export PROBE_HTTP_FALLBACK="${PROBE_HTTP_FALLBACK:-true}"
export PROBE_TIMEOUT="${PROBE_TIMEOUT:-12}"
export PROBE_TRIES="${PROBE_TRIES:-12}"
export PROBE_DELAY="${PROBE_DELAY:-5}"

if [ "${TRAEFIK_ENABLED:-false}" = "true" ] && [ -n "$ROUTER" ] && [ -n "$DOMAIN_EFFECTIVE" ]; then
  echo "================================================================"
  echo "Running Traefik probe..."
  echo "================================================================"
  if "$TRAEFIK_DIR/probe-traefik.sh" post "$ROUTER" "$DOMAIN_EFFECTIVE" "$SERVICE_PORT" "$PROBE_PATH"; then
    :
  else
    status=$?
    echo "::warning::Traefik probe failed (exit code $status)" >&2
  fi
else
  echo "::notice::Traefik probe skipped (TRAEFIK_ENABLED=$TRAEFIK_ENABLED, router='$ROUTER', domain='$DOMAIN_EFFECTIVE')."
fi
