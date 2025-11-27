#!/usr/bin/env bash
set -euo pipefail

INSTALL_PORTAINER="${INSTALL_PORTAINER:-true}"
if [ "$INSTALL_PORTAINER" != "true" ]; then
  echo "::notice::INSTALL_PORTAINER=$INSTALL_PORTAINER; skipping Portainer installation" >&2
  exit 0
fi

PORTAINER_TAG="${PORTAINER_TAG:-lts}"
PORTAINER_HTTPS_PORT="${PORTAINER_HTTPS_PORT:-9443}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-traefik-network}"
# Optional subdomain used when exposing Portainer via Traefik. Example:
#   PORTAINER_DOMAIN=portainer.example.com
# will attach Traefik labels so the UI is reachable at
#   https://portainer.example.com
# in addition to the direct HTTPS binding on :9443.
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
PORTAINER_DATA_DIR="${PORTAINER_DATA_DIR:-$HOME/.local/share/portainer}"

if ! command -v podman >/dev/null 2>&1; then
  echo "::error::podman is not installed; Portainer requires Podman on the host" >&2
  exit 1
fi

mkdir -p "$PORTAINER_DATA_DIR"

# Compute a simple configuration signature so we can avoid unnecessary
# reinstallation when nothing material has changed. Include PORTAINER_DOMAIN
# so that changing the Traefik host (for example from portainer.dev.example.com
# to portainer.example.com) forces a Quadlet/container refresh.
CONF_INPUT="${PORTAINER_TAG}|${PORTAINER_HTTPS_PORT}|${TRAEFIK_NETWORK_NAME}|${PORTAINER_DATA_DIR}|${PORTAINER_DOMAIN}"
PORTAINER_CONFIG_HASH="$CONF_INPUT"
if command -v sha256sum >/dev/null 2>&1; then
  PORTAINER_CONFIG_HASH=$(printf '%s' "$CONF_INPUT" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  PORTAINER_CONFIG_HASH=$(printf '%s' "$CONF_INPUT" | shasum -a 256 | awk '{print $1}')
fi

# Fast path: if an existing Portainer container is running, has a matching
# config hash label, and responds on the expected HTTPS port, skip any
# changes to avoid unnecessary reloads.
if podman container exists portainer >/dev/null 2>&1; then
  status=$(podman inspect -f '{{.State.Status}}' portainer 2>/dev/null || echo "")
  existing_hash=$(podman inspect -f '{{ index .Config.Labels "org.uactions.portainer.confighash" }}' portainer 2>/dev/null || echo "")
  if [ "$status" = "running" ] && [ -n "$existing_hash" ] && [ "$existing_hash" = "$PORTAINER_CONFIG_HASH" ]; then
    healthy="unknown"
    if command -v curl >/dev/null 2>&1; then
      code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 6 "https://127.0.0.1:${PORTAINER_HTTPS_PORT}" || echo "000")
      if [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
        healthy="yes"
      else
        healthy="no:$code"
      fi
    fi
    if [ "$healthy" = "yes" ]; then
      echo "✅ Portainer already running and healthy on https://127.0.0.1:${PORTAINER_HTTPS_PORT} (config hash match); skipping reinstall." >&2
      exit 0
    fi
    echo "::notice::Existing Portainer container detected (status=$status, health=$healthy); will recreate unit and container." >&2
  fi
fi

# If a Portainer container exists but either the config hash changed or it is
# not healthy, stop and remove it so we can recreate with the new settings.
if podman container exists portainer >/dev/null 2>&1; then
  echo "Stopping existing Portainer container ..." >&2
  podman stop portainer >/dev/null 2>&1 || true
  echo "Removing existing Portainer container ..." >&2
  podman rm portainer >/dev/null 2>&1 || true
fi

if [ -n "$TRAEFIK_NETWORK_NAME" ]; then
  if ! podman network exists "$TRAEFIK_NETWORK_NAME" >/dev/null 2>&1; then
    echo "Creating Podman network: $TRAEFIK_NETWORK_NAME" >&2
    podman network create "$TRAEFIK_NETWORK_NAME" >/dev/null
  fi
fi

# Before publishing the HTTPS port, ensure nothing else on the host is already
# bound to it (other than a prior Portainer instance we just removed). This
# avoids confusing port conflicts.
if command -v ss >/dev/null 2>&1; then
  if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)'"${PORTAINER_HTTPS_PORT}"'$'; then
    echo "::error::Portainer HTTPS port ${PORTAINER_HTTPS_PORT} is already in use on this host; aborting Portainer setup." >&2
    echo "       Choose a different portainer_https_port value or free the port before re-running." >&2
    exit 1
  fi
fi

QUADLET_DIR="${HOME}/.config/containers/systemd"
mkdir -p "$QUADLET_DIR"
# Quadlet uses a .container unit file (portainer.container) which systemd
# then exposes as a regular service unit (portainer.service). The .container
# file lives under ~/.config/containers/systemd while the user interacts with
# the generated service via `systemctl --user` using the .service name.
UNIT_PATH="${QUADLET_DIR}/portainer.container"

cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Portainer CE (container management UI)
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/portainer/portainer-ce:${PORTAINER_TAG}
ContainerName=portainer
Volume=%h/.local/share/portainer:/data:Z
Volume=%t/podman/podman.sock:/var/run/docker.sock:Z
PublishPort=${PORTAINER_HTTPS_PORT}:9443
EOF

if [ -n "$TRAEFIK_NETWORK_NAME" ]; then
  printf 'Network=%s
' "$TRAEFIK_NETWORK_NAME" >>"$UNIT_PATH"
fi

cat >>"$UNIT_PATH" <<EOF
Label=app=portainer
Label=managed-by=uactions
Label=org.uactions.portainer.confighash=${PORTAINER_CONFIG_HASH}
EOF

# When a PORTAINER_DOMAIN is provided (for example portainer.shakohub.com),
# attach Traefik labels so the Portainer service is also reachable via HTTPS
# on 443 at that host. The service itself listens on HTTP 9000 inside the
# traefik-network and Traefik terminates TLS and ACME. Example:
#   PORTAINER_DOMAIN=portainer.example.com → https://portainer.example.com
if [ -n "$PORTAINER_DOMAIN" ]; then
  cat >>"$UNIT_PATH" <<EOF
Label=traefik.enable=true
Label=traefik.http.routers.portainer.entrypoints=websecure
Label=traefik.http.routers.portainer.rule=Host("${PORTAINER_DOMAIN}")
Label=traefik.http.routers.portainer.tls=true
Label=traefik.http.routers.portainer.tls.certresolver=letsencrypt
Label=traefik.http.services.portainer.loadbalancer.server.port=9000
EOF
fi

cat >>"$UNIT_PATH" <<EOF

[Install]
WantedBy=default.target
EOF

echo "Portainer Quadlet unit written to ${UNIT_PATH}" >&2

if command -v loginctl >/dev/null 2>&1; then
  CURRENT_USER="$(id -un)"
  if ! loginctl show-user "$CURRENT_USER" 2>/dev/null | grep -q "Linger=yes"; then
    loginctl enable-linger "$CURRENT_USER" >/dev/null 2>&1 || true
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  # When a Quadlet .container file is present under ~/.config/containers/systemd,
  # systemd's generators expose it as a corresponding .service unit. For
  # portainer.container this becomes portainer.service, which is what
  # `systemctl --user` should manage.
  PORTAINER_SERVICE="portainer.service"
  if systemctl --user daemon-reload >/dev/null 2>&1; then
    if ! systemctl --user list-unit-files "${PORTAINER_SERVICE}" --no-legend 2>/dev/null | grep -q "${PORTAINER_SERVICE}"; then
      echo "::warning::Portainer Quadlet unit ${UNIT_PATH} written but ${PORTAINER_SERVICE} was not registered by systemd generators (no matching unit files). Portainer will not be managed by user-level systemd on this host until Quadlet/user-generator behavior is fixed." >&2
    elif systemctl --user start "${PORTAINER_SERVICE}" >/dev/null 2>&1; then
      echo "Started ${PORTAINER_SERVICE} for user (from Quadlet ${UNIT_PATH})" >&2
      # Best-effort HTTPS probe so operators see whether the UI is reachable
      # on the expected address without failing the script when curl is
      # unavailable or the probe times out.
      if command -v curl >/dev/null 2>&1; then
        sleep 3
        code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 "https://127.0.0.1:${PORTAINER_HTTPS_PORT}" || echo "000")
        echo "Portainer HTTPS probe on https://127.0.0.1:${PORTAINER_HTTPS_PORT}: HTTP ${code}" >&2
        echo "Note: If this URL is reachable on the host but not from your browser, ensure your cloud firewall/security group allows inbound TCP ${PORTAINER_HTTPS_PORT} to this instance (in addition to UFW rules)." >&2
      fi
    else
      echo "::warning::Failed to start ${PORTAINER_SERVICE}; start manually with: systemctl --user start ${PORTAINER_SERVICE}" >&2
    fi
  else
    echo "::warning::systemctl --user daemon-reload failed; Quadlet changes may not be active until next reload" >&2
  fi
else
  echo "::warning::systemctl not found; Portainer Quadlet unit created but not registered" >&2
fi
