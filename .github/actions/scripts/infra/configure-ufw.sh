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
  SUDO="sudo -n"
fi

# Fail-fast if we cannot escalate for UFW operations
if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO" ]; then
  echo '::error::UFW configuration requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Install UFW and enable it manually on the server (as root), then re-run:' >&2
  echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
  echo '  sudo apt-get install -y ufw' >&2
  echo '  sudo ufw --force enable' >&2
  exit 1
fi

# Install UFW only if missing
if ! command -v ufw >/dev/null 2>&1; then
  echo "🔧 Installing UFW ..."
  # Allow Release metadata changes so noninteractive apt-get update calls do
  # not fail when trusted repositories evolve.
  $SUDO apt-get update -y --allow-releaseinfo-change >/dev/null 2>&1 || true
  $SUDO apt-get install -y ufw || true
fi

# Helper to check if a rule exists (simple grep match)
rule_exists() {
  local needle="$1"
  $SUDO ufw status | grep -Fq "$needle"
}

# Helper to check if a specific inbound port is allowed for 'Anywhere'
# This prevents 'ALLOW FWD' rules from being confused with 'ALLOW (inbound)'
port_allowed_anywhere() {
  local p="$1"
  # Match: "<port> ALLOW Anywhere" or "<port>/tcp ALLOW Anywhere"
  # Look for lines starting with the port, then whitespace, then 'ALLOW', then 'Anywhere'
  # We use grep -iE for case-insensitive extended regex
  $SUDO ufw status | grep -iE "^\s*${p}(/tcp|/udp)?\s+ALLOW\s+Anywhere" >/dev/null 2>&1
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

if [ "${DEBUG:-false}" = "true" ]; then echo "🔒 Ensuring SSH access is allowed (OpenSSH or 22/tcp) ..."; fi
rule_exists "OpenSSH" || $SUDO ufw allow OpenSSH >/dev/null 2>&1 || true
rule_exists "22/tcp" || $SUDO ufw allow 22/tcp >/dev/null 2>&1 || true
# If a non-standard SSH port is used, allow it explicitly as well
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
  if ! rule_exists "$SSH_PORT/tcp"; then
    [ "${DEBUG:-false}" = "true" ] && echo "🔓 Allowing SSH port $SSH_PORT/tcp"
    $SUDO ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1 || true
  fi
fi

# Enable UFW only if inactive
if ! $SUDO ufw status | grep -qi "Status: active"; then
  echo "🟢 Enabling UFW ..."
  $SUDO ufw --force enable || true
fi

if [ "${DEBUG:-false}" = "true" ]; then echo "➡️ Ports requested to allow: ${UFW_ALLOW_PORTS:-<none>}"; fi
if [ -n "$UFW_ALLOW_PORTS" ]; then
  for port in $UFW_ALLOW_PORTS; do
    [ -z "$port" ] && continue
    # Use the more specific port_allowed_anywhere check to avoid false positives
    # from forward (route) rules.
    if ! port_allowed_anywhere "$port"; then
      [ "${DEBUG:-false}" = "true" ] && echo "🔓 Allowing port $port"
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
  if [ "${DEBUG:-false}" = "true" ]; then echo "🌉 Forwarding in on ${WAN_IFACE_USE} -> out on ${PODMAN_IFACE_USE} for ports: ${ROUTE_PORTS}"; fi
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
  $SUDO ufw reload >/dev/null 2>&1 || true
fi

echo "✅ UFW configured"
if [ "${DEBUG:-false}" = "true" ]; then
  echo "🔎 ufw status"
  $SUDO ufw status
fi
