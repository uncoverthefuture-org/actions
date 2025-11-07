#!/usr/bin/env bash
# request-certbot-cert-wrapper.sh - Wrapper for certbot certificate request with pre/post checks
# Runs checks, calls the main certbot script, and reloads Apache
set -euo pipefail

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
EXTRA_DOMAINS="${EXTRA_DOMAINS:-}"
STAGING="${STAGING:-false}"

echo "🔧 Certbot certificate request wrapper"
echo "  • Domain: $DOMAIN"
echo "  • Email: $EMAIL"
echo "  • Extra domains: ${EXTRA_DOMAINS:-<none>}"
echo "  • Staging: $STAGING"

echo ""
echo "🔎 Checking certbot installation ..."
if ! command -v certbot >/dev/null 2>&1; then
  echo 'Error: certbot is not installed. Run install-certbot first.' >&2
  exit 1
fi
echo "✅ certbot found"

echo ""
echo "🔎 Checking Apache2 service ..."
if ! systemctl status apache2 >/dev/null 2>&1; then
  echo 'Error: apache2 service is required for the Apache plugin.' >&2
  exit 1
fi
echo "✅ apache2 service is running"

echo ""
echo "🚀 Executing main certbot script ..."
"$HOME/uactions/scripts/infra/request-certbot-cert.sh"

echo ""
echo "🔄 Reloading Apache2 ..."
# SUDO detection and reload as needed
IS_ROOT="no"
if [ "$(id -u)" -eq 0 ]; then IS_ROOT="yes"; fi
SUDO=""
if [ "$IS_ROOT" = "no" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi
if [ "$IS_ROOT" = "no" ] && [ -z "$SUDO" ]; then
  echo '::error::Reloading Apache requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Reload manually on the server (as root), then re-run if needed:' >&2
  echo '  sudo systemctl reload apache2' >&2
  exit 1
fi
$SUDO systemctl reload apache2
echo "✅ Apache2 reloaded"
