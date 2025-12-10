#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install-quadlet-sockets.sh - Rootless Traefik socket-activation (quadlet)
# ----------------------------------------------------------------------------
# Purpose:
#   Install systemd user quadlet units to run Traefik via socket activation:
#     - http.socket (ListenStream=80, FileDescriptorName=web)
#     - https.socket (ListenStream=443, FileDescriptorName=websecure)
#     - traefik.container (Traefik container with fd:// entrypoints)
#     - <network>.network (Podman network for Traefik + apps)
#
# Inputs (env):
#   TRAEFIK_VERSION           - Traefik image tag (default: v3.5.4)
#   TRAEFIK_ENABLE_ACME       - true|false (default: true)
#   TRAEFIK_EMAIL             - Email for ACME (required if ACME enabled)
#   TRAEFIK_NETWORK_NAME      - Podman network name (default: traefik-network)
#   QUADLET_ENABLE_HTTP3      - true|false (default: false) adds UDP 443 to https.socket
#
# Exit codes:
#   0 - Success
#   1 - Validation failure
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../util/podman.sh
source "${SCRIPT_DIR}/../util/podman.sh"

TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.5.4}"
TRAEFIK_ENABLE_ACME="${TRAEFIK_ENABLE_ACME:-true}"
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
TRAEFIK_NETWORK_NAME="${TRAEFIK_NETWORK_NAME:-traefik-network}"
QUADLET_ENABLE_HTTP3="${QUADLET_ENABLE_HTTP3:-false}"

# Decide which host resolv.conf to reuse inside the Quadlet-managed Traefik
# container so that ACME DNS lookups (for example, acme-v02.api.letsencrypt.org)
# use the same resolvers as the host instead of the Podman bridge DNS. On
# Ubuntu with systemd-resolved, /run/systemd/resolve/resolv.conf typically
# contains the real upstream nameservers, while /etc/resolv.conf often points
# at the 127.0.0.53 stub. Example:
#   - Host:   nameserver 67.207.67.2  (DigitalOcean)
#   - Inside: Volume=/run/systemd/resolve/resolv.conf:/etc/resolv.conf:ro
# This keeps ACME HTTP-01 flows working even when the Podman bridge DNS
# (for example 10.89.0.1) cannot reach the internet.
HOST_RESOLV_CONF=""
if [[ -r /run/systemd/resolve/resolv.conf ]]; then
  HOST_RESOLV_CONF="/run/systemd/resolve/resolv.conf"
elif [[ -r /etc/resolv.conf ]]; then
  HOST_RESOLV_CONF="/etc/resolv.conf"
fi

if [[ "$TRAEFIK_ENABLE_ACME" == "true" && -z "$TRAEFIK_EMAIL" ]]; then
  echo "Error: TRAEFIK_EMAIL is required when TRAEFIK_ENABLE_ACME=true" >&2
  exit 1
fi

CURRENT_USER="$(id -un)"
PUID="$(id -u)"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$PUID}"
QUADLET_DIR="${HOME}/.config/containers/systemd"
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
SOCK_HOST="${XDG_RUNTIME_DIR}/podman/podman.sock"

mkdir -p "$QUADLET_DIR" "$USER_SYSTEMD_DIR"

# Before installing new Quadlet units, best-effort clean up any existing
# Traefik container or user-level service so we do not end up with multiple
# instances competing for ports 80/443. This is intentionally conservative
# and does not touch system-level services, but does emit a warning if one is
# detected so operators can migrate fully to the Quadlet model.
if command -v podman >/dev/null 2>&1; then
  podman stop traefik >/dev/null 2>&1 || true
  podman rm   traefik >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user stop traefik.service  >/dev/null 2>&1 || true
  systemctl --user disable traefik.service >/dev/null 2>&1 || true
  if systemctl is-active --quiet traefik.service 2>/dev/null; then
    echo "::warning::A system-level traefik.service is active; it may conflict with rootless Quadlet Traefik on ports 80/443. Consider disabling the system service or migrating fully to Quadlet." >&2
  fi
fi

# Best-effort: assert socket and SELinux hints if available
if [[ -x "$HOME/uactions/scripts/traefik/assert-socket-and-selinux.sh" ]]; then
  "$HOME/uactions/scripts/traefik/assert-socket-and-selinux.sh" || true
fi

# Network unit
NETWORK_UNIT_PATH="${QUADLET_DIR}/${TRAEFIK_NETWORK_NAME}.network"
cat >"$NETWORK_UNIT_PATH" <<EOF
[Unit]
Description=Podman network ${TRAEFIK_NETWORK_NAME}

[Network]
NetworkName=${TRAEFIK_NETWORK_NAME}
# Options=isolate=true
# Internal=false
EOF

# http.socket (port 80)
HTTP_SOCKET_PATH="${USER_SYSTEMD_DIR}/http.socket"
cat >"$HTTP_SOCKET_PATH" <<'EOF'
[Unit]
Description=Traefik HTTP socket (port 80)

[Socket]
ListenStream=80
FileDescriptorName=web
Service=traefik.service
Accept=no

[Install]
WantedBy=default.target
EOF

# https.socket (port 443)
HTTPS_SOCKET_PATH="${USER_SYSTEMD_DIR}/https.socket"
{
  cat <<'EOF'
[Unit]
Description=Traefik HTTPS socket (port 443)

[Socket]
ListenStream=443
EOF
  if [[ "${QUADLET_ENABLE_HTTP3}" == "true" ]]; then
    echo "ListenDatagram=443"  # enable HTTP/3 (QUIC)
  fi
  cat <<'EOF'
FileDescriptorName=websecure
Service=traefik.service
Accept=no

[Install]
WantedBy=default.target
EOF
} >"$HTTPS_SOCKET_PATH"

# traefik.container
CONTAINER_UNIT_PATH="${QUADLET_DIR}/traefik.container"
cat >"$CONTAINER_UNIT_PATH" <<EOF
[Unit]
Description=Traefik reverse proxy (socket-activated)
# Quadlet maps ${TRAEFIK_NETWORK_NAME}.network to a generated
# ${TRAEFIK_NETWORK_NAME}-network.service unit under the user generator. Use
# the latter name in dependencies to avoid Invalid argument warnings from
# systemd when it attempts to wire up traefik-network.network directly.
After=${TRAEFIK_NETWORK_NAME}-network.service http.socket https.socket
Wants=${TRAEFIK_NETWORK_NAME}-network.service http.socket https.socket

[Service]
# Ensure config directories and files exist before starting Traefik.
# This prevents exit 137 (SIGKILL) when config files are missing.
ExecStartPre=/bin/bash -c 'mkdir -p %h/.config/traefik %h/.local/share/traefik'
ExecStartPre=/bin/bash -c 'test -f %h/.local/share/traefik/acme.json || echo "{}" > %h/.local/share/traefik/acme.json'
ExecStartPre=/bin/bash -c 'chmod 600 %h/.local/share/traefik/acme.json 2>/dev/null || true'
# Create minimal traefik.yml if missing (ACME/dashboard configured via CLI args)
ExecStartPre=/bin/bash -c 'test -f %h/.config/traefik/traefik.yml || printf "log:\\n  level: INFO\\nping:\\n  entryPoint: web\\n" > %h/.config/traefik/traefik.yml'
# Give Traefik time to cleanly start before marking ready
TimeoutStartSec=60
# Restart policy with backoff to prevent tight restart loops
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=5

[Container]
Image=docker.io/traefik:${TRAEFIK_VERSION}
ContainerName=traefik
# Prevent pulling from registry on restart - use only locally cached images.
Pull=never

# Resource Limits: Prevent system crashes by capping usage and disabling swap
# (so containers are OOM killed instead of locking the OS).
Memory=512M
PodmanArgs=--memory-swap=512M
# SELinux: disable label separation for socket volume access under rootless
SecurityLabelDisable=true
EOF

# Append CPU limit if the host supports it
if podman_cpu_cgroup_available; then
  echo "PodmanArgs=--cpus=1.0" >>"$CONTAINER_UNIT_PATH"
fi

cat >>"$CONTAINER_UNIT_PATH" <<EOF
# Volumes: static config and ACME storage (user-scoped)
Volume=%h/.config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
Volume=%h/.local/share/traefik/acme.json:/letsencrypt/acme.json:Z
# Podman (Docker-compatible) socket for provider discovery (user-scoped)
Volume=%t/podman/podman.sock:/var/run/docker.sock:Z
# Optional: reuse host DNS configuration inside Traefik so outbound ACME
# requests resolve correctly. When HOST_RESOLV_CONF is set (for example
# /run/systemd/resolve/resolv.conf on Ubuntu with systemd-resolved), this
# line expands to a Volume mount such as:
#   Volume=/run/systemd/resolve/resolv.conf:/etc/resolv.conf:ro
${HOST_RESOLV_CONF:+Volume=${HOST_RESOLV_CONF}:/etc/resolv.conf:ro}

# Network join
Network=${TRAEFIK_NETWORK_NAME}

# EntryPoints via systemd sockets (fd://)
Exec=--entrypoints.web.address=fd://web
Exec=--entrypoints.websecure.address=fd://websecure

# Providers (Docker over Podman socket)
Exec=--providers.docker.endpoint=unix:///var/run/docker.sock
Exec=--providers.docker.exposedByDefault=false

# API dashboard (not exposed by default; controlled by static file if desired)
Exec=--api.dashboard=true

# Metrics entrypoint (optional; controlled by static file if present)
# Exec=--entrypoints.metrics.address=:8082

EOF

if [[ "$TRAEFIK_ENABLE_ACME" == "true" ]]; then
  cat >>"$CONTAINER_UNIT_PATH" <<EOF
# ACME settings and redirect web->websecure
Exec=--entrypoints.web.http.redirections.entryPoint.to=websecure
Exec=--entrypoints.web.http.redirections.entryPoint.scheme=https
Exec=--certificatesresolvers.letsencrypt.acme.email=${TRAEFIK_EMAIL}
Exec=--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
Exec=--certificatesresolvers.letsencrypt.acme.httpchallenge.entryPoint=web
Exec=--entrypoints.websecure.http.tls.certResolver=letsencrypt

EOF
fi

cat >>"$CONTAINER_UNIT_PATH" <<'EOF'
[Install]
WantedBy=default.target
EOF

# Reload and enable units. These operations are best-effort so that differences
# in how Quadlet exposes network units (for example, ${TRAEFIK_NETWORK_NAME}-network.service
# vs ${TRAEFIK_NETWORK_NAME}.network) or transient user@.service quirks do not
# cause the installer to fail outright. We rely on downstream preflight checks
# (ensure-traefik-ready.sh) to validate listeners on 80/443.
if ! systemctl --user daemon-reload >/dev/null 2>&1; then
  echo "::warning::systemctl --user daemon-reload failed; Quadlet changes may not be active until next reload." >&2
fi

# Network unit: some Podman/Quadlet versions expose the generated service as
# "${TRAEFIK_NETWORK_NAME}-network.service" instead of "${TRAEFIK_NETWORK_NAME}.network".
# We attempt the intuitive name but treat failure as informational only.
if ! systemctl --user start "${TRAEFIK_NETWORK_NAME}.network" >/dev/null 2>&1; then
  echo "::notice::Could not start ${TRAEFIK_NETWORK_NAME}.network; on some systems the Quadlet-generated service is named ${TRAEFIK_NETWORK_NAME}-network.service or the network is created lazily by Podman. Continuing without treating this as fatal." >&2
fi

# Start sockets for 80/443; if this fails, emit a warning but avoid aborting so
# that subsequent diagnostics can still run.
if ! systemctl --user start http.socket https.socket >/dev/null 2>&1; then
  echo "::warning::Failed to start http.socket/https.socket via systemctl --user; Traefik may not be socket-activated until these units are started manually." >&2
fi

# Optional: start service (will also be socket-activated on demand). We enable
# the Quadlet-generated traefik.service after explicitly stopping/disabling any
# prior user unit earlier in this script.
systemctl --user start traefik.service >/dev/null 2>&1 || true

# Show status summary
echo "Installed quadlet units in ${QUADLET_DIR}:"
ls -1 "${QUADLET_DIR}" | sed 's/^/  - /'

# Quick probe (best-effort)
sleep 1
if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$'; then echo "Port 80 socket active"; else echo "::warning::Port 80 socket not visible yet"; fi
if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)443$'; then echo "Port 443 socket active"; else echo "::warning::Port 443 socket not visible yet"; fi

exit 0
