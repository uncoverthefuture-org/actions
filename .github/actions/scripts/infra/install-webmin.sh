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
  echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
  echo '  sudo apt-get install -y gnupg wget apt-transport-https software-properties-common' >&2
  echo '  wget -qO- https://download.webmin.com/jcameron-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/webmin.gpg' >&2
  echo "  echo 'deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib' | sudo tee /etc/apt/sources.list.d/webmin.list" >&2
  echo '  sudo apt-get update -y --allow-releaseinfo-change' >&2
  echo '  sudo apt-get install -y webmin usermin' >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
echo "📥 Updating apt cache and installing prerequisites ..."
# Allow Release metadata changes (for example, Label/Suite) so noninteractive
# apt-get update runs do not fail when trusted repositories evolve.
$SUDO apt-get update -y --allow-releaseinfo-change -o Dpkg::Use-Pty=0 || true
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

has_webmin_repo() {
  # Detect whether the Webmin APT repository is already present. This keeps the
  # setup idempotent and allows users to pre-configure the repo (for example,
  # via cloud-init) without this script overwriting their configuration.
  if grep -Rqs 'download.webmin.com' /etc/apt/sources.list.d /etc/apt/sources.list 2>/dev/null; then
    return 0
  fi
  return 1
}

ensure_webmin_repo() {
  echo "🔑 Ensuring Webmin repository is configured ..."
  if has_webmin_repo; then
    echo "✅ Webmin APT repository already configured; skipping setup script"
    return 0
  fi
  echo "🔑 Setting up Webmin repository via vendor script ..."
  # Use vendor setup script to configure repo and keys
  # Fetch the vendor repo setup script
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
  # Run setup script (adds repo + keys). Use -f to avoid interactive
  # confirmation prompts so this remains non-interactive in CI.
  if ! $SUDO sh "$TMP_SETUP" -f >/dev/null 2>&1; then
    echo "::error::webmin-setup-repo.sh failed to configure repository" >&2
    echo "Please try manually: curl -fsSL -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh && sudo sh webmin-setup-repo.sh -f" >&2
    rm -f "$TMP_SETUP"
    exit 1
  fi
  rm -f "$TMP_SETUP"
  # Verify that the setup script actually registered the Webmin repository.
  # On some images the helper may no-op; in that case, apply the documented
  # manual configuration so that apt can locate the webmin package.
  if has_webmin_repo; then
    echo "✅ Webmin APT repository configured via vendor script"
    return 0
  fi
  echo "::warning::webmin-setup-repo.sh completed but Webmin APT repository was not detected; applying manual repository configuration fallback" >&2
  # Manual repo setup (equivalent to the instructions printed in error hints).
  # This path is idempotent: it overwrites the webmin.list entry and keyring
  # if they already exist, so repeated runs are safe.
  $SUDO rm -f /etc/apt/sources.list.d/webmin.list /etc/apt/sources.list.d/webmin.list.disabled 2>/dev/null || true
  # Ensure keyrings directory exists for the signed-by stanza
  $SUDO mkdir -p /usr/share/keyrings 2>/dev/null || true
  if command -v curl >/dev/null 2>&1; then
    $SUDO sh -c "curl -fsSL https://download.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg"
  else
    $SUDO sh -c "wget -qO- https://download.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg"
  fi
  $SUDO sh -c "echo 'deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib' > /etc/apt/sources.list.d/webmin.list"
  if has_webmin_repo; then
    echo "✅ Webmin APT repository configured via manual fallback"
    return 0
  fi
  echo "::error::Failed to configure Webmin APT repository even after manual fallback" >&2
  return 1
}

if [ "$INSTALL_WEBMIN" = "true" ] || [ "$INSTALL_USERMIN" = "true" ]; then
  ensure_webmin_repo
  echo "📥 Updating apt cache for Webmin repo ..."
  # Use --allow-releaseinfo-change to avoid failures when the Webmin repository
  # adjusts its Release metadata between runs.
  UPDATE_OUT="$($SUDO apt-get update -y --allow-releaseinfo-change -o Dpkg::Use-Pty=0 2>&1)" || UPDATE_RC=$?
  : "${UPDATE_RC:=0}"
  if [ "$UPDATE_RC" -ne 0 ]; then
    if printf '%s' "$UPDATE_OUT" | grep -qiE 'untrusted public key algorithm: dsa|repository .* is not signed|NO_PUBKEY|GPG error'; then
      echo "::error::Apt update failed due to Webmin repository signature issues" >&2
      echo "================================================================" >&2
      echo "Manual fix (run on the server as a user with sudo):" >&2
      echo "================================================================" >&2
      echo "sudo rm -f /etc/apt/sources.list.d/webmin.list /etc/apt/sources.list.d/webmin.list.disabled /usr/share/keyrings/webmin.gpg /etc/apt/keyrings/webmin.gpg" >&2
      echo "curl -fsSL -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh" >&2
      echo "sudo sh webmin-setup-repo.sh -f" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change" >&2
      echo "sudo apt-get install -y webmin${INSTALL_USERMIN:+ usermin}" >&2
      echo "================================================================" >&2
      echo "If that still fails and you accept the risk, you can use this fallback:" >&2
      echo "echo 'deb [trusted=yes] https://download.webmin.com/download/repository sarge contrib' | sudo tee /etc/apt/sources.list.d/webmin.list" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true" >&2
      echo "sudo apt-get install -y webmin${INSTALL_USERMIN:+ usermin}" >&2
      echo "================================================================" >&2
    else
      echo "::error::Apt update failed while preparing Webmin repository" >&2
      printf '%s\n' "$UPDATE_OUT" | tail -n 80 >&2 || true
    fi
    exit 1
  fi
fi

if [ "$INSTALL_WEBMIN" = "true" ]; then
  echo "📦 Installing Webmin ..."
  if ! INSTALL_OUT="$($SUDO apt-get install -y --install-recommends -o Dpkg::Use-Pty=0 webmin 2>&1)"; then
    if printf '%s' "$INSTALL_OUT" | grep -qiE 'untrusted public key algorithm: dsa|repository .* is not signed|NO_PUBKEY|GPG error'; then
      echo "::error::Webmin installation failed due to repository signature issues" >&2
      echo "================================================================" >&2
      echo "Manual fix (run on the server as a user with sudo):" >&2
      echo "================================================================" >&2
      echo "sudo rm -f /etc/apt/sources.list.d/webmin.list /etc/apt/sources.list.d/webmin.list.disabled /usr/share/keyrings/webmin.gpg /etc/apt/keyrings/webmin.gpg" >&2
      echo "curl -fsSL -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh" >&2
      echo "sudo sh webmin-setup-repo.sh" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change" >&2
      echo "sudo apt-get install -y webmin${INSTALL_USERMIN:+ usermin}" >&2
      echo "================================================================" >&2
      echo "If that still fails and you accept the risk, you can use this fallback:" >&2
      echo "echo 'deb [trusted=yes] https://download.webmin.com/download/repository sarge contrib' | sudo tee /etc/apt/sources.list.d/webmin.list" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true" >&2
      echo "sudo apt-get install -y webmin${INSTALL_USERMIN:+ usermin}" >&2
      echo "================================================================" >&2
    else
      echo "::error::apt-get install webmin failed" >&2
      printf '%s\n' "$INSTALL_OUT" | tail -n 80 >&2 || true
    fi
    echo "::error::apt-get install webmin failed" >&2
    exit 1
  fi
  if ! dpkg -s webmin >/dev/null 2>&1; then
    echo "::error::Webmin installation verification failed (dpkg -s webmin)" >&2
    exit 1
  fi
  echo "✅ Webmin installed"
fi

if [ "$INSTALL_USERMIN" = "true" ]; then
  echo "📦 Installing Usermin ..."
  if ! INSTALL_OUT2="$($SUDO apt-get install -y -o Dpkg::Use-Pty=0 usermin 2>&1)"; then
    if printf '%s' "$INSTALL_OUT2" | grep -qiE 'untrusted public key algorithm: dsa|repository .* is not signed|NO_PUBKEY|GPG error'; then
      echo "::error::Usermin installation failed due to repository signature issues" >&2
      echo "================================================================" >&2
      echo "Manual fix (run on the server as a user with sudo):" >&2
      echo "================================================================" >&2
      echo "sudo rm -f /etc/apt/sources.list.d/webmin.list /etc/apt/sources.list.d/webmin.list.disabled /usr/share/keyrings/webmin.gpg /etc/apt/keyrings/webmin.gpg" >&2
      echo "curl -fsSL -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh" >&2
      echo "sudo sh webmin-setup-repo.sh" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change" >&2
      echo "sudo apt-get install -y usermin" >&2
      echo "================================================================" >&2
      echo "If that still fails and you accept the risk, you can use this fallback:" >&2
      echo "echo 'deb [trusted=yes] https://download.webmin.com/download/repository sarge contrib' | sudo tee /etc/apt/sources.list.d/webmin.list" >&2
      echo "sudo apt-get update -y --allow-releaseinfo-change -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true" >&2
      echo "sudo apt-get install -y usermin" >&2
      echo "================================================================" >&2
    else
      echo "::error::apt-get install usermin failed" >&2
      printf '%s\n' "$INSTALL_OUT2" | tail -n 80 >&2 || true
    fi
    echo "::error::apt-get install usermin failed" >&2
    exit 1
  fi
  if ! dpkg -s usermin >/dev/null 2>&1; then
    echo "::error::Usermin installation verification failed (dpkg -s usermin)" >&2
    exit 1
  fi
  echo "🟢 Enabling and restarting usermin service ..."
  $SUDO systemctl enable usermin || true
  $SUDO systemctl restart usermin || true
  echo "✅ Usermin installed and started"
fi
