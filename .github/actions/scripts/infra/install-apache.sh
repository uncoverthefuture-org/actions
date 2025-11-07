#!/usr/bin/env bash
# install-apache.sh - Install Apache2 web server
set -euo pipefail

echo "🔧 Starting Apache2 installation ..."
IS_ROOT="no"
if [ "$(id -u)" -eq 0 ]; then IS_ROOT="yes"; fi
SUDO=""
if [ "$IS_ROOT" = "no" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi
if [ "$IS_ROOT" = "no" ] && [ -z "$SUDO" ]; then
  echo '::error::Apache installation requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Install manually on the server (as root), then re-run:' >&2
  echo '  sudo apt-get update -y' >&2
  echo '  sudo apt-get install -y apache2 libapache2-mod-wsgi-py3' >&2
  exit 1
fi
echo "📥 Updating apt cache ..."
$SUDO apt-get update -y
echo "📦 Installing apache2 and mod_wsgi ..."
$SUDO apt-get install -y apache2 libapache2-mod-wsgi-py3

echo "✅ Apache2 installed"
echo "🔎 apache2 -v"
apache2 -v
