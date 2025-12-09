#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../util/podman.sh
source "${SCRIPT_DIR}/../util/podman.sh"

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

# Admin bootstrap controls. When PORTAINER_ADMIN_AUTO_INIT=true (default) the
# script attempts to initialize the Portainer admin user via the HTTPS API on
# first install using the /api/users/admin/init endpoint. Callers can override
# the username/password via environment variables; when no password is
# provided, a convenience default of 12345678 is used and a prominent warning
# is emitted so operators know to change it immediately in production.
PORTAINER_ADMIN_AUTO_INIT="${PORTAINER_ADMIN_AUTO_INIT:-true}"
PORTAINER_ADMIN_USERNAME="${PORTAINER_ADMIN_USERNAME:-admin}"
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-}"
if [ "$PORTAINER_ADMIN_AUTO_INIT" = "true" ] && [ -z "$PORTAINER_ADMIN_PASSWORD" ]; then
  echo "::warning::PORTAINER_ADMIN_AUTO_INIT=true and no PORTAINER_ADMIN_PASSWORD provided; using default password '12345678'. Change this in production immediately after first login or override via PORTAINER_ADMIN_PASSWORD." >&2
  PORTAINER_ADMIN_PASSWORD="12345678"
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "::error::podman is not installed; Portainer requires Podman on the host" >&2
  exit 1
fi

mkdir -p "$PORTAINER_DATA_DIR"

# Compute a simple configuration signature so we can avoid unnecessary
# reinstallation when nothing material has changed. Include PORTAINER_DOMAIN
# so that changing the Traefik host (for example from portainer.dev.example.com
# to portainer.example.com) forces a Quadlet/container refresh. Append a
# static version token so that changes in label syntax (for example switching
# the Traefik rule to Host(`domain`)) also trigger a refresh.
CONF_INPUT="v2|${PORTAINER_TAG}|${PORTAINER_HTTPS_PORT}|${TRAEFIK_NETWORK_NAME}|${PORTAINER_DATA_DIR}|${PORTAINER_DOMAIN}"
PORTAINER_CONFIG_HASH="$CONF_INPUT"
if command -v sha256sum >/dev/null 2>&1; then
  PORTAINER_CONFIG_HASH=$(printf '%s' "$CONF_INPUT" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  PORTAINER_CONFIG_HASH=$(printf '%s' "$CONF_INPUT" | shasum -a 256 | awk '{print $1}')
fi

# Fast path: if an existing Portainer container is running, has a matching
# config hash label, and responds on the expected HTTPS port with a 2xx HTTP
# status code, skip any changes to avoid unnecessary reloads. Non-2xx codes
# (including the first-time "timed out for security purposes" screen or other
# error pages) are treated as not healthy so that rerunning the action can
# safely recreate the service and re-attempt admin initialization.
if podman container exists portainer >/dev/null 2>&1; then
  status=$(podman inspect -f '{{.State.Status}}' portainer 2>/dev/null || echo "")
  existing_hash=$(podman inspect -f '{{ index .Config.Labels "org.uactions.portainer.confighash" }}' portainer 2>/dev/null || echo "")
  if [ "$status" = "running" ] && [ -n "$existing_hash" ] && [ "$existing_hash" = "$PORTAINER_CONFIG_HASH" ]; then
    healthy="unknown"
    if command -v curl >/dev/null 2>&1; then
      code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 6 "https://127.0.0.1:${PORTAINER_HTTPS_PORT}" || echo "000")
      if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        healthy="yes:$code"
      else
        healthy="no:$code"
      fi
    fi
    if [ "${healthy%%:*}" = "yes" ]; then
      echo "✅ Portainer already running and healthy on https://127.0.0.1:${PORTAINER_HTTPS_PORT} (HTTP ${healthy#*:}, config hash match); skipping reinstall." >&2
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

# Allow Portainer port in UFW if UFW is installed and active
if command -v ufw >/dev/null 2>&1; then
  echo "🔓 Allowing Portainer HTTPS port ${PORTAINER_HTTPS_PORT}/tcp in UFW ..." >&2
  if command -v sudo >/dev/null 2>&1; then
    sudo -n ufw allow "${PORTAINER_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
  else
    ufw allow "${PORTAINER_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
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
# Persist Portainer state (including admin credentials and configuration)
# under the user-scoped data directory. Example:
#   PORTAINER_DATA_DIR="$HOME/.local/share/portainer" → /data inside container
# This directory should be treated as sensitive on the host.
#
# Prevent pulling from registry on restart - use only locally cached images.
# This prevents restart failures when the registry is unreachable or unauthenticated.
# Prevent pulling from registry on restart - use only locally cached images.
# This prevents restart failures when the registry is unreachable or unauthenticated.
Pull=never

# Resource Limits: Prevent system crashes by capping usage and disabling swap
# (so containers are OOM killed instead of locking the OS).
Memory=512M
PodmanArgs=--memory-swap=512M
EOF

# Append CPU limit if the host supports it
if podman_cpu_cgroup_available; then
  echo "PodmanArgs=--cpus=0.5" >>"$UNIT_PATH"
fi

cat >>"$UNIT_PATH" <<EOF
Volume=%h/.local/share/portainer:/data:Z
Volume=%t/podman/podman.sock:/var/run/docker.sock:Z
# Publish HTTPS UI directly on the host (e.g. https://server:${PORTAINER_HTTPS_PORT}).
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
# on 443 at that host. In this configuration Traefik terminates the public
# TLS handshake and then talks HTTPS to Portainer on port 9443 inside the
# traefik-network. Example:
#   PORTAINER_DOMAIN=portainer.example.com → https://portainer.example.com
if [ -n "$PORTAINER_DOMAIN" ]; then
  cat >>"$UNIT_PATH" <<EOF
Label=traefik.enable=true
Label=traefik.http.routers.portainer.entrypoints=websecure
Label=traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)
Label=traefik.http.routers.portainer.tls=true
Label=traefik.http.routers.portainer.tls.certresolver=letsencrypt
# Tell Traefik to talk HTTPS to Portainer on 9443 inside the container.
Label=traefik.http.services.portainer.loadbalancer.server.port=9443
Label=traefik.http.services.portainer.loadbalancer.server.scheme=https
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

        # When admin auto-initialization is enabled, bootstrap the Portainer
        # admin user via the HTTPS API on fresh installations so operators do
        # not need to race the five-minute UI timeout. The /api/users/admin/init
        # endpoint only succeeds before an admin user exists; subsequent runs
        # are idempotent and we treat non-2xx responses as notices instead of
        # hard failures.
        if [ "$PORTAINER_ADMIN_AUTO_INIT" = "true" ]; then
          if [ -z "$PORTAINER_ADMIN_PASSWORD" ]; then
            echo "::warning::PORTAINER_ADMIN_AUTO_INIT=true but PORTAINER_ADMIN_PASSWORD is empty; skipping admin bootstrap (no password available)." >&2
          elif [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
            payload=""
            if command -v jq >/dev/null 2>&1; then
              payload=$(jq -nc --arg u "$PORTAINER_ADMIN_USERNAME" --arg p "$PORTAINER_ADMIN_PASSWORD" '{username:$u,password:$p}')
            else
              # Fallback JSON construction for environments without jq. This
              # assumes the username/password do not contain double quotes.
              payload=$(printf '{"username":"%s","password":"%s"}' "$PORTAINER_ADMIN_USERNAME" "$PORTAINER_ADMIN_PASSWORD")
            fi

            admin_code=$(curl -ksS -o /tmp/portainer-admin-init.out -w '%{http_code}' --max-time 10 \
              -H 'Content-Type: application/json' \
              -X POST "https://127.0.0.1:${PORTAINER_HTTPS_PORT}/api/users/admin/init" \
              --data "$payload" || echo "000")

            if [ "$admin_code" -ge 200 ] && [ "$admin_code" -lt 300 ]; then
              echo "✅ Portainer admin auto-initialized via API for user '${PORTAINER_ADMIN_USERNAME}' (HTTP ${admin_code})." >&2
            else
              echo "::notice::Portainer admin auto-init returned HTTP ${admin_code}; this usually means the admin user already exists or the instance is not in initial-setup state. Verify Portainer login manually if unsure." >&2
            fi
          else
            echo "::notice::Skipping Portainer admin auto-init because HTTPS probe did not return 2xx (HTTP ${code})." >&2
          fi
        fi
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

# Surface the Portainer data directory and security expectations in logs so
# operators know where credentials live and how the initial admin user is
# created. When PORTAINER_ADMIN_AUTO_INIT=true the first admin user is created
# via the API using either the provided PORTAINER_ADMIN_PASSWORD or the
# convenience default of 12345678. Operators should treat this directory as
# sensitive and change the admin password immediately after first login.
echo " Portainer data directory: ${PORTAINER_DATA_DIR} (treat as secret; contains Portainer state and admin credentials)." >&2
if [ "$PORTAINER_ADMIN_AUTO_INIT" = "true" ]; then
  echo " Portainer admin auto-init: enabled (initial user '${PORTAINER_ADMIN_USERNAME}', password from PORTAINER_ADMIN_PASSWORD or default '12345678'). Change this password immediately in production." >&2
else
  echo " Portainer admin auto-init: disabled (create the admin user via the Portainer UI or API before exposing the service)." >&2
fi
