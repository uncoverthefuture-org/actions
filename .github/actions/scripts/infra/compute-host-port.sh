#!/usr/bin/env bash
# compute-host-port.sh - Compute effective host port with fallback chain
set -euo pipefail

HOST_PORT_IN="${HOST_PORT_IN:-}"
WEB_HOST_PORT="${WEB_HOST_PORT:-}"
PORT="${PORT:-}"
ENV_NAME="${ENV_NAME:-}"

echo "🔧 Computing host port"
echo "  • Inputs: HOST_PORT_IN='${HOST_PORT_IN:-}' WEB_HOST_PORT='${WEB_HOST_PORT:-}' PORT='${PORT:-}' ENV_NAME='${ENV_NAME:-}'"

# Compute effective host port
SOURCE=""
if [ -n "$HOST_PORT_IN" ]; then
  HOST_PORT="$HOST_PORT_IN"
  SOURCE="HOST_PORT_IN"
elif [ -n "$WEB_HOST_PORT" ]; then
  HOST_PORT="$WEB_HOST_PORT"
  SOURCE="WEB_HOST_PORT"
elif [ -n "$PORT" ]; then
  HOST_PORT="$PORT"
  SOURCE="PORT"
else
  # Default based on environment
  case "$ENV_NAME" in
    production) HOST_PORT="80" ;;
    staging) HOST_PORT="8080" ;;
    development) HOST_PORT="3000" ;;
    *) HOST_PORT="3000" ;;
  esac
  SOURCE="ENV_DEFAULT"
fi

# Output to GitHub Actions
echo "host_port=$HOST_PORT" >> "$GITHUB_OUTPUT"

echo "✅ Computed host port: $HOST_PORT (source=$SOURCE)"
