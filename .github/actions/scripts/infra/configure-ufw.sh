#!/usr/bin/env bash
# configure-ufw.sh - Configure UFW firewall and open specified ports
set -euo pipefail

UFW_ALLOW_PORTS="${UFW_ALLOW_PORTS:-}"
SSH_PORT="${SSH_PORT:-22}"
ENABLE_PODMAN_FORWARD="${ENABLE_PODMAN_FORWARD:-true}"
ROUTE_PORTS="${ROUTE_PORTS:-80 443}"
SET_FORWARD_POLICY_ACCEPT="${SET_FORWARD_POLICY_ACCEPT:-true}"
WAN_IFACE_IN="${WAN_IFACE:-}"
PODMAN_IFACE_IN="${PODMAN_IFACE:-}"

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

# Detect interfaces if not provided
detect_wan_iface() {
  local wan
  wan=$(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $5}') || true
  if [ -z "$wan" ]; then wan="eth0"; fi
  echo "$wan"
}

detect_podman_iface() {
  local piface
  piface=$(ip -br link 2>/dev/null | awk '$1 ~ /^podman[0-9]+/ {print $1; exit}') || true
  if [ -z "$piface" ]; then piface="podman1"; fi
  echo "$piface"
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

# Optionally set DEFAULT_FORWARD_POLICY to ACCEPT for NAT/bridging
if [ "${SET_FORWARD_POLICY_ACCEPT}" = "true" ]; then
  if [ -f /etc/default/ufw ]; then
    if ! grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw; then
      echo "🛠️ Setting DEFAULT_FORWARD_POLICY=\"ACCEPT\" in /etc/default/ufw"
      $SUDO sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
    fi
  fi
fi

# Add UFW route rules to allow forwarding from WAN -> Podman bridge on key ports
if [ "${ENABLE_PODMAN_FORWARD}" = "true" ]; then
  WAN_IFACE_USE="$WAN_IFACE_IN"
  PODMAN_IFACE_USE="$PODMAN_IFACE_IN"
  [ -z "$WAN_IFACE_USE" ] && WAN_IFACE_USE="$(detect_wan_iface)"
  [ -z "$PODMAN_IFACE_USE" ] && PODMAN_IFACE_USE="$(detect_podman_iface)"
  echo "🌉 Forwarding in on ${WAN_IFACE_USE} -> out on ${PODMAN_IFACE_USE} for ports: ${ROUTE_PORTS}"
  for p in $ROUTE_PORTS; do
    [ -z "$p" ] && continue
    # best-effort idempotence check
    if $SUDO ufw status verbose | grep -iq "in on ${WAN_IFACE_USE} .*out on ${PODMAN_IFACE_USE}.* ${p}/tcp"; then
      :
    else
      $SUDO ufw route allow in on "${WAN_IFACE_USE}" out on "${PODMAN_IFACE_USE}" proto tcp to any port "$p" || true
    fi
  done
  # Reload to ensure route rules are active
  $SUDO ufw reload || true
fi

echo "✅ UFW configured"
echo "🔎 ufw status"
$SUDO ufw status
