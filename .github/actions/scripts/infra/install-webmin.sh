#!/usr/bin/env bash
# install-webmin.sh - Install Webmin/Usermin (controlled via env vars)
set -euo pipefail

INSTALL_WEBMIN=${INSTALL_WEBMIN:-false}
INSTALL_USERMIN=${INSTALL_USERMIN:-false}

echo "🔧 Webmin/Usermin installation toggles: INSTALL_WEBMIN=$INSTALL_WEBMIN INSTALL_USERMIN=$INSTALL_USERMIN"
IS_ROOT="no"
if [ "$(id -u)" -eq 0 ]; then IS_ROOT="yes"; fi
SUDO=""
if [ "$IS_ROOT" = "no" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi
if [ "$IS_ROOT" = "no" ] && [ -z "$SUDO" ]; then
  echo '::error::Webmin/Usermin installation requires root privileges; current session cannot escalate.' >&2
  echo "Detected: user=$(id -un); sudo(non-interactive)=no" >&2
  echo 'Install manually on the server (as root), then re-run:' >&2
  echo '  sudo apt-get update -y' >&2
  echo '  sudo apt-get install -y gnupg wget apt-transport-https software-properties-common' >&2
  echo '  wget -qO- https://download.webmin.com/jcameron-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/webmin.gpg' >&2
  echo "  echo 'deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib' | sudo tee /etc/apt/sources.list.d/webmin.list" >&2
  echo '  sudo apt-get update -y' >&2
  echo '  sudo apt-get install -y webmin usermin' >&2
  exit 1
fi
echo "📥 Updating apt cache and installing prerequisites ..."
$SUDO apt-get update -y
$SUDO apt-get install -y gnupg wget apt-transport-https software-properties-common

ensure_webmin_repo() {
  if [ ! -f /usr/share/keyrings/webmin.gpg ]; then
    echo "🔑 Adding Webmin repository key ..."
    wget -qO- https://download.webmin.com/jcameron-key.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  else
    echo "🔑 Webmin key already present"
  fi
  if [ ! -f /etc/apt/sources.list.d/webmin.list ]; then
    echo "🧭 Adding Webmin repository to sources.list.d ..."
    echo 'deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib' | $SUDO tee /etc/apt/sources.list.d/webmin.list >/dev/null
  else
    echo "🧭 Webmin repository already configured"
  fi
}

if [ "$INSTALL_WEBMIN" = "true" ] || [ "$INSTALL_USERMIN" = "true" ]; then
  ensure_webmin_repo
  echo "📥 Updating apt cache for Webmin repo ..."
  $SUDO apt-get update -y
fi

if [ "$INSTALL_WEBMIN" = "true" ]; then
  echo "📦 Installing Webmin ..."
  $SUDO apt-get install -y webmin || true
  echo "✅ Webmin installed"
fi

if [ "$INSTALL_USERMIN" = "true" ]; then
  echo "📦 Installing Usermin ..."
  $SUDO apt-get install -y usermin || true
  echo "🟢 Enabling and restarting usermin service ..."
  $SUDO systemctl enable usermin || true
  $SUDO systemctl restart usermin || true
  echo "✅ Usermin installed and started"
fi
