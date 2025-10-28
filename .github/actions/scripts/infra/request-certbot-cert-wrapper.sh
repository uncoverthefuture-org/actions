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
/opt/uactions/scripts/infra/request-certbot-cert.sh

echo ""
echo "🔄 Reloading Apache2 ..."
systemctl reload apache2
echo "✅ Apache2 reloaded"
