#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# ensure-traefik-config.sh - Rebuild Traefik static config and ACME storage
# ----------------------------------------------------------------------------
# Purpose:
#   Regenerates the user-scoped traefik.yml from the canonical install template
#   (or system copy) each run so we never miss critical sections like ping.
#   Keeps acme.json readable with 0600 permissions, reusing existing cert data.
#
# Behavior:
#   - Verifies /etc/traefik/traefik.yml exists and is readable
#   - Verifies /var/lib/traefik/acme.json exists and is readable
#   - Warns when permissions or ownership would prevent Traefik from using the
#     files and suggests running install-traefik.sh as root
#   - Logs whether the configuration was reused or missing
# ----------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../util/traefik.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYS_CONFIG="/etc/traefik/traefik.yml"
SYS_ACME="/var/lib/traefik/acme.json"
CONFIG_PATH="$HOME/.config/traefik/traefik.yml"
ACME_PATH="$HOME/.local/share/traefik/acme.json"
SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
fi

# Helper: install content with correct ownership/perms even when target is root-owned.
# Example: install_user_file "$TMP" "$CONFIG_PATH" 640 "Traefik user config"
install_user_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  local desc="$4"
  if install -m "$mode" "$src" "$dest" 2>/dev/null; then
    return 0
  fi
  if [ -n "$SUDO" ]; then
    if $SUDO install -m "$mode" -o "$(id -u)" -g "$(id -g)" "$src" "$dest" 2>/dev/null; then
      return 0
    fi
  fi
  echo "::error::Cannot write ${desc} to $dest (permission denied)." >&2
  exit 1
}

mkdir -p "$(dirname "$CONFIG_PATH")" "$(dirname "$ACME_PATH")"

CONFIG_TMP="$(mktemp -t traefik-config.XXXXXX)"
ACME_TMP=""
LOG_LEVEL="${TRAEFIK_LOG_LEVEL:-DEBUG}"

cleanup_tmp() {
  rm -f "$CONFIG_TMP" "$CONFIG_TMP.bak"
  if [ -n "$ACME_TMP" ]; then rm -f "$ACME_TMP"; fi
}
trap cleanup_tmp EXIT

generate_traefik_static_config "$CONFIG_TMP" "${TRAEFIK_EMAIL:-}" "$LOG_LEVEL" "${TRAEFIK_UTIL_DEBUG:-}"
if [ -z "${TRAEFIK_EMAIL:-}" ]; then
  echo "::warning::TRAEFIK_EMAIL not provided; leaving placeholder ${TRAEFIK_EMAIL} in traefik.yml." >&2
else
  echo "📝 Generated Traefik config template with email ${TRAEFIK_EMAIL}"
fi

# Attempt to keep the system config in sync when sudo is available.
if [ -n "$SUDO" ]; then
  if ! $SUDO test -d "$(dirname "$SYS_CONFIG")"; then
    $SUDO mkdir -p "$(dirname "$SYS_CONFIG")"
  fi
  if ! $SUDO test -f "$SYS_CONFIG" || ! cmp -s "$CONFIG_TMP" "$SYS_CONFIG"; then
    $SUDO install -m 0644 "$CONFIG_TMP" "$SYS_CONFIG"
    echo "🔧 Installed canonical Traefik config to $SYS_CONFIG"
  else
    echo "✅ System Traefik config already matches template"
  fi
else
  if [ -r "$SYS_CONFIG" ] && ! cmp -s "$CONFIG_TMP" "$SYS_CONFIG"; then
    echo "::warning::System config differs from template but sudo is unavailable. Run install-traefik.sh as root to resync." >&2
  fi
fi

# Install the regenerated config with predictable permissions (0640 keeps it user-readable).
install_user_file "$CONFIG_TMP" "$CONFIG_PATH" 0640 "Traefik user config"
echo "✅ Ensured Traefik static config at $CONFIG_PATH"

if [ "${TRAEFIK_RESET_ACME:-false}" = "true" ]; then
  ACME_TMP="$(mktemp -t traefik-acme.XXXXXX)"
  if [ -f "$ACME_PATH" ]; then
    cp "$ACME_PATH" "${ACME_PATH}.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    echo "🧨 TRAEFIK_RESET_ACME=true; backing up existing ACME storage and creating a fresh store."
  else
    echo "🧨 TRAEFIK_RESET_ACME=true; creating fresh ACME storage at $ACME_PATH."
  fi
  printf '{}' >"$ACME_TMP"
  install_user_file "$ACME_TMP" "$ACME_PATH" 0600 "Traefik ACME storage"
  echo "✅ Reset ACME storage at $ACME_PATH"
elif [ -f "$ACME_PATH" ]; then
  if [ -n "$SUDO" ]; then
    $SUDO chmod 600 "$ACME_PATH" >/dev/null 2>&1 || true
  else
    chmod 600 "$ACME_PATH" >/dev/null 2>&1 || true
  fi
  echo "🔐 Reusing existing ACME storage: $ACME_PATH"
else
  ACME_TMP="$(mktemp -t traefik-acme.XXXXXX)"
  if [ -r "$SYS_ACME" ]; then
    cp "$SYS_ACME" "$ACME_TMP" 2>/dev/null || true
    echo "🔐 Copied system ACME storage into user scope"
  elif [ -n "$SUDO" ] && $SUDO test -r "$SYS_ACME" 2>/dev/null; then
    $SUDO cat "$SYS_ACME" >"$ACME_TMP"
    echo "🔐 Copied system ACME storage into user scope"
  else
    printf '{}' >"$ACME_TMP"
    echo "🆕 Created empty ACME storage template ({})"
  fi
  install_user_file "$ACME_TMP" "$ACME_PATH" 0600 "Traefik ACME storage"
  echo "✅ Ensured ACME storage at $ACME_PATH"
fi
