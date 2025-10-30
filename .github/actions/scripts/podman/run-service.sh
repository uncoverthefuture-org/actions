#!/usr/bin/env bash
# run-service.sh - Run a long-lived service container via Podman
set -euo pipefail

IMAGE="${IMAGE:-}"
SERVICE_NAME="${SERVICE_NAME:-}"
PORTS="${PORTS:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
RESTART_POLICY="${RESTART_POLICY:-unless-stopped}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
ENV_FILE="${ENV_FILE:-}"
VOLUMES="${VOLUMES:-}"
COMMAND="${COMMAND:-}"

if [ -z "$IMAGE" ] || [ -z "$SERVICE_NAME" ]; then
  echo "Error: IMAGE and SERVICE_NAME are required" >&2
  exit 1
fi

echo "🔧 Preparing to run service"
echo "  • Service:   $SERVICE_NAME"
echo "  • Image:     $IMAGE"
echo "  • Env file:  ${ENV_FILE:-<none>}"
echo "  • Restart:   $RESTART_POLICY"
echo "  • Memory:    $MEMORY_LIMIT"

# Stop/remove if exists
echo "🛑 Stopping existing service (if any): $SERVICE_NAME"
podman stop "$SERVICE_NAME" >/dev/null 2>&1 || true
echo "🧹 Removing existing service (if any): $SERVICE_NAME"
podman rm "$SERVICE_NAME" >/dev/null 2>&1 || true

# Build port args (ignore empty or malformed entries)
PORT_ARGS=()
INVALID_PORTS=()
if [ -n "$PORTS" ]; then
  for port_mapping in $PORTS; do
    [ -z "$port_mapping" ] && continue
    if [[ "$port_mapping" =~ ^[0-9]+:[0-9]+(/(tcp|udp))?$ ]]; then
      PORT_ARGS+=( -p "$port_mapping" )
    else
      INVALID_PORTS+=("$port_mapping")
    fi
  done
fi

if [ ${#INVALID_PORTS[@]} -gt 0 ]; then
  echo '::error::Invalid port mapping syntax detected in PORTS.' >&2
  printf 'Invalid entries:%s\n' " ${INVALID_PORTS[*]}" >&2
  echo "Hint: Use numeric host:container mappings like '8080:80' (optionally append /tcp or /udp)." >&2
  exit 1
fi

if [ ${#PORT_ARGS[@]} -gt 0 ]; then
  echo "🔓 Publishing ports: ${PORTS}"
else
  echo "🔓 Publishing ports: <none>"
fi

# Build volume args from newline-separated specs
VOL_ARGS=()
if [ -n "$VOLUMES" ]; then
  # Read VOLUMES variable line by line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    VOL_ARGS+=( -v "$line" )
  done <<< "$VOLUMES"
fi
if [ ${#VOL_ARGS[@]} -gt 0 ]; then
  echo "🗂  Mounting volumes:" && printf '   - %s\n' $(printf '%q ' $(echo "$VOLUMES" | tr '\n' ' '))
else
  echo "🗂  Mounting volumes: <none>"
fi

# Run container
echo "🚀 Starting service: $SERVICE_NAME"
podman run -d --name "$SERVICE_NAME" \
  ${ENV_FILE:+--env-file "$ENV_FILE"} \
  "${PORT_ARGS[@]}" \
  "${VOL_ARGS[@]}" \
  --restart="$RESTART_POLICY" \
  --memory="$MEMORY_LIMIT" --memory-swap="$MEMORY_LIMIT" \
  ${EXTRA_ARGS:+$EXTRA_ARGS} \
  "$IMAGE" ${COMMAND:+$COMMAND}

echo " Service $SERVICE_NAME started"
echo " Service details:"
echo ""
podman ps --filter name="$SERVICE_NAME" --format 'table {{.ID}}	{{.Status}}	{{.Names}}	{{.Ports}}'
