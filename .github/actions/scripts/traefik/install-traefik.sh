#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install-traefik.sh - Root-level Traefik installation and system setup
# ----------------------------------------------------------------------------
# Purpose:
#   Install Traefik system configuration as root user.
#   Creates directories, writes config files, sets permissions.
#   Validates system readiness for user-level Traefik operation.
#
# Inputs (environment variables):
#   TRAEFIK_EMAIL       - Email for Let's Encrypt account (REQUIRED)
#   PODMAN_USER         - Linux user that runs containers (default: deployer)
#   DASHBOARD_USER      - Optional username for Traefik dashboard basic auth (default: admin)
#   DASHBOARD_PASS_BCRYPT - Optional bcrypt hash (htpasswd -nB) for dashboard user; if absent a placeholder file is created
#
# Exit codes:
#   0 - Success
#   1 - Missing requirements or runtime error
# ----------------------------------------------------------------------------
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Resolve inputs -----------------------------------------------------------------
# Get required environment variables with defaults
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-}"
PODMAN_USER="${PODMAN_USER:-deployer}"
DASHBOARD_USER="${DASHBOARD_USER:-admin}"
DASHBOARD_PASS_BCRYPT="${DASHBOARD_PASS_BCRYPT:-}"

# Validate required inputs
if [[ -z "$TRAEFIK_EMAIL" ]]; then
  echo "Error: TRAEFIK_EMAIL is required" >&2
  exit 1
fi

# --- Preconditions ------------------------------------------------------------------
# Check if we can perform privileged operations (either root or sudo access)
if [ "$(id -un)" = "root" ]; then
  SUDO_CMD=""  # No sudo needed when running as root
  echo "🔧 Installing Traefik system configuration (running as root)"
elif sudo -n true 2>/dev/null; then
  SUDO_CMD="sudo"  # Use sudo for privileged operations
  echo "🔧 Installing Traefik system configuration (running as $(id -un) with sudo)"
else
  # Cannot perform privileged operations
  echo "❌ ERROR: This script requires root privileges or sudo access to perform system operations." >&2
  echo "   Either run as root, or ensure $(id -un) has sudo access for systemctl, mkdir, chown operations." >&2
  exit 1
fi

echo "🔧 Installing Traefik system configuration"

# Stop legacy proxies that might occupy 80/443 (ignore errors)
echo "🧹 Stopping legacy proxies (apache2, nginx) if present ..."
# Check if apache2 is active before trying to stop it
if $SUDO_CMD systemctl is-active --quiet apache2 2>/dev/null; then
  $SUDO_CMD systemctl stop apache2
  echo "  ✓ Stopped apache2 service"
else
  echo "  ✓ apache2 already stopped or not installed"
fi
# Check if nginx is active before trying to stop it
if $SUDO_CMD systemctl is-active --quiet nginx 2>/dev/null; then
  $SUDO_CMD systemctl stop nginx
  echo "  ✓ Stopped nginx service"
else
  echo "  ✓ nginx already stopped or not installed"
fi
# Disable services to prevent auto-start
$SUDO_CMD systemctl disable apache2 nginx >/dev/null 2>&1 || true

# --- Filesystem layout ---------------------------------------------------------------
echo "📁 Creating Traefik directories ..."
# Check if directories already exist before creating
if [ ! -d "/etc/traefik" ]; then
  $SUDO_CMD mkdir -p /etc/traefik
  echo "  ✓ Created /etc/traefik"
else
  echo "  ✓ /etc/traefik already exists"
fi
if [ ! -d "/var/lib/traefik" ]; then
  $SUDO_CMD mkdir -p /var/lib/traefik
  echo "  ✓ Created /var/lib/traefik"
else
  echo "  ✓ /var/lib/traefik already exists"
fi

echo "📝 Writing Traefik config to /etc/traefik/traefik.yml ..."
CONFIG_TMP="$(mktemp)"
trap 'rm -f "$CONFIG_TMP"' EXIT
cat >"$CONFIG_TMP" <<'EOF'
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  dashboard:
    address: ":8080"
  metrics:
    address: ":8082"

providers:
  podman:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

api:
  dashboard: true
  insecure: false

metrics:
  prometheus:
    entryPoint: "metrics"
    addRoutersLabels: true
    addServicesLabels: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

http:
  middlewares:
    internal-dashboard-auth:
      basicAuth:
        usersFile: "/etc/traefik/dashboard-users"

  routers:
    internal-dashboard:
      entryPoints:
        - dashboard
      rule: "PathPrefix(`/`)"
      middlewares:
        - internal-dashboard-auth
      service: "api@internal"
      tls: {}

  services: {}
EOF

if [[ -n "$SUDO_CMD" ]]; then
  $SUDO_CMD cp "$CONFIG_TMP" /etc/traefik/traefik.yml
else
  cp "$CONFIG_TMP" /etc/traefik/traefik.yml
fi
echo "  ✓ Config written to /etc/traefik/traefik.yml"

echo "👥 Preparing dashboard basic-auth users file ..."
DASHBOARD_USERS_FILE="/etc/traefik/dashboard-users"
if [[ -n "$DASHBOARD_PASS_BCRYPT" ]]; then
  DASHBOARD_ENTRY="${DASHBOARD_USER}:${DASHBOARD_PASS_BCRYPT}"
  printf '%s\n' "$DASHBOARD_ENTRY" | $SUDO_CMD tee "$DASHBOARD_USERS_FILE" >/dev/null
  echo "  ✓ Dashboard credentials written for user '${DASHBOARD_USER}'"
else
  $SUDO_CMD tee "$DASHBOARD_USERS_FILE" >/dev/null <<'EOF'
# Add bcrypt entries (htpasswd -nB <user>) to enable dashboard access.
# Example:
# admin:$2y$05$abcdefghijklmnopqrstuv1234567890abcdefghijklmno
EOF
  echo "::warning::No DASHBOARD_PASS_BCRYPT provided; wrote placeholder dashboard-users file. Update it with htpasswd entries before enabling dashboard."
fi
$SUDO_CMD chmod 640 "$DASHBOARD_USERS_FILE"
$SUDO_CMD chown "$PODMAN_USER:$PODMAN_USER" "$DASHBOARD_USERS_FILE"

echo "🔐 Preparing ACME storage ..."
# Check if ACME file exists and has correct permissions
if [ ! -f "/var/lib/traefik/acme.json" ]; then
  $SUDO_CMD touch /var/lib/traefik/acme.json
  echo "  ✓ Created /var/lib/traefik/acme.json"
else
  echo "  ✓ /var/lib/traefik/acme.json already exists"
fi
# Ensure correct permissions (600 for security)
if [ "$($SUDO_CMD stat -c '%a' /var/lib/traefik/acme.json 2>/dev/null || echo '000')" != "600" ]; then
  $SUDO_CMD chmod 600 /var/lib/traefik/acme.json
  echo "  ✓ Set permissions to 600 on acme.json"
else
  echo "  ✓ acme.json already has correct permissions (600)"
fi

# Change ownership of Traefik directories to podman user
echo "👤 Setting ownership of Traefik directories to $PODMAN_USER ..."
# Check current ownership before changing
if ! $SUDO_CMD stat -c '%U' /etc/traefik/traefik.yml 2>/dev/null | grep -q "^$PODMAN_USER$"; then
  $SUDO_CMD chown -R "$PODMAN_USER:$PODMAN_USER" /etc/traefik /var/lib/traefik
  echo "  ✓ Changed ownership to $PODMAN_USER"
else
  echo "  ✓ Ownership already set to $PODMAN_USER"
fi

# --- Validation ----------------------------------------------------------------------
echo "✅ Validating Traefik installation ..."

# Check directories exist and have correct ownership
if [ ! -d "/etc/traefik" ] || [ ! -d "/var/lib/traefik" ]; then
  echo "Error: Traefik directories not created" >&2
  exit 1
fi

# Check config file exists and is readable by podman user
if [ ! -f "/etc/traefik/traefik.yml" ]; then
  echo "Error: Traefik config file not created" >&2
  exit 1
fi

# Check ownership of config file
if ! $SUDO_CMD stat -c '%U' /etc/traefik/traefik.yml | grep -q "^$PODMAN_USER$"; then
  echo "Error: Traefik config not owned by $PODMAN_USER" >&2
  exit 1
fi

# Check ownership of ACME storage
if ! $SUDO_CMD stat -c '%U' /var/lib/traefik/acme.json | grep -q "^$PODMAN_USER$"; then
  echo "Error: ACME storage not owned by $PODMAN_USER" >&2
  exit 1
fi

# Check permissions (acme.json should be 600)
if [ "$($SUDO_CMD stat -c '%a' /var/lib/traefik/acme.json)" != "600" ]; then
  echo "Error: ACME storage has incorrect permissions" >&2
  exit 1
fi

echo "✅ Traefik system configuration installed and validated"
echo "📁 Config: /etc/traefik/traefik.yml (owned by $PODMAN_USER)"
echo "🔐 ACME: /var/lib/traefik/acme.json (600 permissions)"
