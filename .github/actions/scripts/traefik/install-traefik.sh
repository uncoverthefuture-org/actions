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
#   TRAEFIK_EMAIL     - Email for Let's Encrypt account (REQUIRED)
#   PODMAN_USER       - Linux user that runs containers (default: deployer)
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
# Write config file with Podman provider configuration
$SUDO_CMD tee /etc/traefik/traefik.yml >/dev/null <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  podman:
    # Traefik will be given access to the Podman API socket via /var/run/docker.sock
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF
echo "  ✓ Config written to /etc/traefik/traefik.yml"

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
