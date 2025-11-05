#!/usr/bin/env bash
# configure-ufw.sh - Configure UFW firewall and open specified ports
set -euo pipefail

UFW_ALLOW_PORTS="${UFW_ALLOW_PORTS:-}"
SSH_PORT="${SSH_PORT:-22}"

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo"
fi

# Install UFW only if missing
if ! command -v ufw >/dev/null 2>&1; then
  echo "🔧 Installing UFW ..."
  $SUDO apt-get update -y >/dev/null 2>&1 || true
  $SUDO apt-get install -y ufw || true
fi

# Helper to check if a rule exists (simple grep match)
rule_exists() {
  local needle="$1"
  $SUDO ufw status | grep -Fq "$needle"
}

echo "🔒 Ensuring SSH access is allowed (OpenSSH or 22/tcp) ..."
rule_exists "OpenSSH" || $SUDO ufw allow OpenSSH >/dev/null 2>&1 || true
rule_exists "22/tcp" || $SUDO ufw allow 22/tcp >/dev/null 2>&1 || true
# If a non-standard SSH port is used, allow it explicitly as well
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
  if ! rule_exists "$SSH_PORT/tcp"; then
    echo "🔓 Allowing SSH port $SSH_PORT/tcp"
    $SUDO ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1 || true
  fi
fi

# Enable UFW only if inactive
if ! $SUDO ufw status | grep -qi "Status: active"; then
  echo "🟢 Enabling UFW ..."
  $SUDO ufw --force enable || true
fi

echo "➡️ Ports requested to allow: ${UFW_ALLOW_PORTS:-<none>}"
if [ -n "$UFW_ALLOW_PORTS" ]; then
  for port in $UFW_ALLOW_PORTS; do
    [ -z "$port" ] && continue
    if ! rule_exists "$port"; then
      echo "🔓 Allowing port $port"
      $SUDO ufw allow "$port" || true
    fi
  done
fi

echo "✅ UFW configured"
echo "🔎 ufw status"
$SUDO ufw status
