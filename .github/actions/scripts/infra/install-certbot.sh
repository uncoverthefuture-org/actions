#!/usr/bin/env bash
# install-certbot.sh - Install Certbot (with Apache plugin) for Let's Encrypt
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo 'Error: Only Debian/Ubuntu apt-based systems are supported' >&2
  exit 1
fi

echo "🔧 Installing Certbot (Apache plugin) ..."
echo "📥 Updating apt cache ..."
apt-get update -y
echo "📦 Installing prerequisite packages ..."
apt-get install -y software-properties-common
echo "➕ Adding Certbot PPA ..."
add-apt-repository -y ppa:certbot/certbot || true
echo "📥 Updating apt cache (post-PPA) ..."
apt-get update -y
echo "📦 Installing certbot and apache plugin ..."
apt-get install -y certbot python3-certbot-apache

echo "✅ Certbot installed"
echo "🔎 certbot --version"
certbot --version
