#!/usr/bin/env bash
# install-certbot.sh - Install Certbot (with Apache plugin) for Let's Encrypt
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo 'Error: Only Debian/Ubuntu apt-based systems are supported' >&2
  exit 1
fi

echo "🔧 Installing Certbot (Apache plugin) ..."
IS_ROOT="no"
if [ "$(id -u)" -eq 0 ]; then IS_ROOT="yes"; fi
SUDO=""
if [ "$IS_ROOT" = "no" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi
if [ "$IS_ROOT" = "no" ] && [ -z "$SUDO" ]; then
  echo '::error::Certbot installation requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Install manually on the server (as root), then re-run:' >&2
  echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
  echo '  sudo apt-get install -y software-properties-common' >&2
  echo '  sudo add-apt-repository -y ppa:certbot/certbot' >&2
  echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
  echo '  sudo apt-get install -y certbot python3-certbot-apache' >&2
  exit 1
fi
echo "📥 Updating apt cache ..."
# Use --allow-releaseinfo-change so repository metadata changes (for example,
# a PPA adjusting its Label) do not cause noninteractive apt-get update runs
# to fail.
$SUDO apt-get update -y --allow-releaseinfo-change
echo "📦 Installing prerequisite packages ..."
$SUDO apt-get install -y software-properties-common
echo "➕ Adding Certbot PPA ..."
$SUDO add-apt-repository -y ppa:certbot/certbot || true
echo "📥 Updating apt cache (post-PPA) ..."
$SUDO apt-get update -y --allow-releaseinfo-change
echo "📦 Installing certbot and apache plugin ..."
$SUDO apt-get install -y certbot python3-certbot-apache

echo "✅ Certbot installed"
echo "🔎 certbot --version"
certbot --version
