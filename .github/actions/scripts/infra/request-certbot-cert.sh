#!/usr/bin/env bash
# request-certbot-cert.sh - Request/Renew SSL certificate via Let's Encrypt (Apache plugin)
set -euo pipefail

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
EXTRA_DOMAINS="${EXTRA_DOMAINS:-}"
STAGING="${STAGING:-false}"

echo "🔎 Checking certbot installation ..."
if ! command -v certbot >/dev/null 2>&1; then
  echo 'Error: certbot is not installed. Run install-certbot first.' >&2
  exit 1
fi

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo 'Error: DOMAIN and EMAIL are required' >&2
  exit 1
fi

echo "➡️ Building domain list ..."
DOM_OPTS=( -d "$DOMAIN" )
if [ -n "$EXTRA_DOMAINS" ]; then
  IFS=',' read -r -a arr <<< "$EXTRA_DOMAINS"
  for d in "${arr[@]}"; do
    d_trim=$(echo "$d" | xargs)
    [ -z "$d_trim" ] && continue
    DOM_OPTS+=( -d "$d_trim" )
  done
fi

echo "🧪 Using staging: $STAGING"
STAGING_FLAG=()
if [ "$STAGING" = "true" ]; then
  STAGING_FLAG=( --staging )
fi

echo "🚀 Requesting/Renewing certificate via Apache plugin for: ${DOM_OPTS[*]}"
certbot --non-interactive --agree-tos --email "$EMAIL" \
  --apache \
  "${STAGING_FLAG[@]}" \
  "${DOM_OPTS[@]}" || true

echo "✅ Certificate request completed for $DOMAIN"
echo "📂 Listing /etc/letsencrypt/live:"
ls -la /etc/letsencrypt/live/ || true
