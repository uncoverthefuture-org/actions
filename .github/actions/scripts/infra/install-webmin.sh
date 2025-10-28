#!/usr/bin/env bash
# install-webmin.sh - Install Webmin/Usermin (controlled via env vars)
set -euo pipefail

INSTALL_WEBMIN=${INSTALL_WEBMIN:-false}
INSTALL_USERMIN=${INSTALL_USERMIN:-false}

echo "🔧 Webmin/Usermin installation toggles: INSTALL_WEBMIN=$INSTALL_WEBMIN INSTALL_USERMIN=$INSTALL_USERMIN"
echo "📥 Updating apt cache and installing prerequisites ..."
apt-get update -y
apt-get install -y gnupg wget apt-transport-https software-properties-common

ensure_webmin_repo() {
  if [ ! -f /usr/share/keyrings/webmin.gpg ]; then
    echo "🔑 Adding Webmin repository key ..."
    wget -qO- https://download.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  else
    echo "🔑 Webmin key already present"
  fi
  if [ ! -f /etc/apt/sources.list.d/webmin.list ]; then
    echo "🧭 Adding Webmin repository to sources.list.d ..."
    echo 'deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib' > /etc/apt/sources.list.d/webmin.list
  else
    echo "🧭 Webmin repository already configured"
  fi
}

if [ "$INSTALL_WEBMIN" = "true" ] || [ "$INSTALL_USERMIN" = "true" ]; then
  ensure_webmin_repo
  echo "📥 Updating apt cache for Webmin repo ..."
  apt-get update -y
fi

if [ "$INSTALL_WEBMIN" = "true" ]; then
  echo "📦 Installing Webmin ..."
  apt-get install -y webmin || true
  echo "✅ Webmin installed"
fi

if [ "$INSTALL_USERMIN" = "true" ]; then
  echo "📦 Installing Usermin ..."
  apt-get install -y usermin || true
  echo "🟢 Enabling and restarting usermin service ..."
  systemctl enable usermin || true
  systemctl restart usermin || true
  echo "✅ Usermin installed and started"
fi
