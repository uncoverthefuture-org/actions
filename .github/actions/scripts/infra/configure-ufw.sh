#!/usr/bin/env bash
# configure-ufw.sh - Configure UFW firewall and open specified ports
set -euo pipefail

UFW_ALLOW_PORTS="${UFW_ALLOW_PORTS:-}"

echo "🔧 Installing UFW ..."
apt-get install -y ufw || true

echo "🔒 Ensuring SSH access is allowed (OpenSSH or 22/tcp) ..."
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true

echo "🟢 Enabling UFW ..."
ufw --force enable || true

echo "➡️ Ports requested to allow: ${UFW_ALLOW_PORTS:-<none>}"
if [ -n "$UFW_ALLOW_PORTS" ]; then
  for port in $UFW_ALLOW_PORTS; do
    [ -z "$port" ] && continue
    echo "🔓 Allowing port $port"
    ufw allow "$port" || true
  done
fi

echo "✅ UFW configured"
echo "🔎 ufw status"
ufw status
