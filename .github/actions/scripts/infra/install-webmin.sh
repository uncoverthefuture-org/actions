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
export DEBIAN_FRONTEND=noninteractive
echo "📥 Updating apt cache and installing prerequisites ..."
$SUDO apt-get update -y -o Dpkg::Use-Pty=0
$SUDO apt-get install -y -o Dpkg::Use-Pty=0 gnupg wget curl ca-certificates apt-transport-https software-properties-common || true

# Idempotence: detect already-installed packages and avoid reinstall
if dpkg -s webmin >/dev/null 2>&1; then
  echo "✅ webmin already installed; will skip reinstallation"
  INSTALL_WEBMIN=false
fi
if dpkg -s usermin >/dev/null 2>&1; then
  echo "✅ usermin already installed; will skip reinstallation"
  INSTALL_USERMIN=false
fi

ensure_webmin_repo() {
  # If repo already configured, skip script setup
  if [ -f /etc/apt/sources.list.d/webmin.list ] || grep -Rqs "download.webmin.com" /etc/apt/sources.list.d /etc/apt/sources.list 2>/dev/null; then
    echo "🧭 Webmin repository already configured"
    return 0
  fi
  echo "🔑 Setting up Webmin repository via vendor script ..."
  TMP_SETUP="$(mktemp -t webmin-setup.XXXXXX.sh)"
  # Prefer curl, fallback to wget
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$TMP_SETUP" https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
  else
    wget -qO "$TMP_SETUP" https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
  fi
  if [ ! -s "$TMP_SETUP" ]; then
    echo "::error::Failed to download webmin-setup-repo.sh (empty file)" >&2
    rm -f "$TMP_SETUP"
    exit 1
  fi
  chmod +x "$TMP_SETUP"
  # Run setup script (adds repo + keys)
  if ! $SUDO sh "$TMP_SETUP" >/dev/null 2>&1; then
    echo "::error::webmin-setup-repo.sh failed to configure repository" >&2
    echo "Please try manually: curl -fsSL -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh && sudo sh webmin-setup-repo.sh" >&2
    rm -f "$TMP_SETUP"
    exit 1
  fi
  rm -f "$TMP_SETUP"
}

if [ "$INSTALL_WEBMIN" = "true" ] || [ "$INSTALL_USERMIN" = "true" ]; then
  ensure_webmin_repo
  echo "📥 Updating apt cache for Webmin repo ..."
  $SUDO apt-get update -y -o Dpkg::Use-Pty=0 || true
fi

if [ "$INSTALL_WEBMIN" = "true" ]; then
  echo "📦 Installing Webmin ..."
  $SUDO apt-get install -y --install-recommends -o Dpkg::Use-Pty=0 webmin || true
  echo "✅ Webmin installed"
fi

if [ "$INSTALL_USERMIN" = "true" ]; then
  echo "📦 Installing Usermin ..."
  $SUDO apt-get install -y -o Dpkg::Use-Pty=0 usermin || true
  echo "🟢 Enabling and restarting usermin service ..."
  $SUDO systemctl enable usermin || true
  $SUDO systemctl restart usermin || true
  echo "✅ Usermin installed and started"
fi
