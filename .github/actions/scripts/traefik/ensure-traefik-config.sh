#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# ensure-traefik-config.sh - Validate Traefik static config and ACME storage
# ----------------------------------------------------------------------------
# Purpose:
#   Ensures required Traefik configuration files exist and are readable before
#   the user-level setup script attempts to start the Traefik container.
#   Emits explicit messaging when existing configuration is detected so that
#   callers know the files are being reused instead of recreated.
#
# Behavior:
#   - Verifies /etc/traefik/traefik.yml exists and is readable
#   - Verifies /var/lib/traefik/acme.json exists and is readable
#   - Warns when permissions or ownership would prevent Traefik from using the
#     files and suggests running install-traefik.sh as root
#   - Logs whether the configuration was reused or missing
# ----------------------------------------------------------------------------
set -euo pipefail

CONFIG_PATH="/etc/traefik/traefik.yml"
ACME_PATH="/var/lib/traefik/acme.json"

if [[ -f "$CONFIG_PATH" ]]; then
  if [[ -r "$CONFIG_PATH" ]]; then
    echo "📄 Reusing existing Traefik config: $CONFIG_PATH"
  else
    echo "❌ ERROR: Traefik config exists at $CONFIG_PATH but is not readable by $(id -un)." >&2
    echo "   Run install-traefik.sh as a privileged user to correct ownership/permissions." >&2
    exit 1
  fi
else
  echo "❌ ERROR: Traefik config missing at $CONFIG_PATH." >&2
  echo "   Run install-traefik.sh as a privileged user before executing setup-traefik.sh." >&2
  exit 1
fi

if [[ -f "$ACME_PATH" ]]; then
  if [[ -r "$ACME_PATH" ]]; then
    PERMS=$(stat -c '%a' "$ACME_PATH" 2>/dev/null || echo "unknown")
    if [[ "$PERMS" != "600" ]]; then
      echo "⚠️  Warning: $ACME_PATH permissions are $PERMS (expected 600)." >&2
      echo "    Update with: sudo chmod 600 $ACME_PATH" >&2
    fi
    echo "🔐 Reusing existing ACME storage: $ACME_PATH"
  else
    echo "❌ ERROR: Traefik ACME storage exists at $ACME_PATH but is not readable by $(id -un)." >&2
    echo "   Run install-traefik.sh as a privileged user to correct ownership/permissions." >&2
    exit 1
  fi
else
  echo "❌ ERROR: Traefik ACME storage missing at $ACME_PATH." >&2
  echo "   Run install-traefik.sh as a privileged user before executing setup-traefik.sh." >&2
  exit 1
fi
