#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# ensure-traefik-config.sh - Validate Traefik static config and ACME storage
# ----------------------------------------------------------------------------
# Purpose:
#   Ensures required Traefik configuration files exist and are readable before
#   the user-level setup script attempts to start the Traefik container.
#   Emits explicit messaging when existing configuration is detected so that
#   callers know the files are being reused instead of recreated.
#
# Behavior:
#   - Verifies /etc/traefik/traefik.yml exists and is readable
#   - Verifies /var/lib/traefik/acme.json exists and is readable
#   - Warns when permissions or ownership would prevent Traefik from using the
#     files and suggests running install-traefik.sh as root
#   - Logs whether the configuration was reused or missing
# ----------------------------------------------------------------------------
set -euo pipefail

CONFIG_PATH="$HOME/.config/traefik/traefik.yml"
ACME_PATH="$HOME/.local/share/traefik/acme.json"
SYS_CONFIG="/etc/traefik/traefik.yml"
SYS_ACME="/var/lib/traefik/acme.json"

mkdir -p "$(dirname "$CONFIG_PATH")" "$(dirname "$ACME_PATH")"

if [[ -f "$CONFIG_PATH" ]]; then
  if [[ -r "$CONFIG_PATH" ]]; then
    echo "📄 Reusing existing Traefik config: $CONFIG_PATH"
  else
    echo "❌ ERROR: Traefik config exists at $CONFIG_PATH but is not readable by $(id -un)." >&2
    exit 1
  fi
else
  if [[ -r "$SYS_CONFIG" ]]; then
    cp "$SYS_CONFIG" "$CONFIG_PATH"
    echo "📄 Copied system config to user scope: $CONFIG_PATH"
  else
    cat >"$CONFIG_PATH" <<'YAML'
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

api: {}
accessLog: {}
YAML
    echo "🆕 Created minimal Traefik config at $CONFIG_PATH"
  fi
fi

if [[ -f "$ACME_PATH" ]]; then
  if [[ -r "$ACME_PATH" ]]; then
    PERMS=$(stat -c '%a' "$ACME_PATH" 2>/dev/null || echo "unknown")
    if [[ "$PERMS" != "600" ]]; then
      echo "⚠️  Warning: $ACME_PATH permissions are $PERMS (expected 600)." >&2
      chmod 600 "$ACME_PATH" >/dev/null 2>&1 || true
    fi
    echo "🔐 Reusing existing ACME storage: $ACME_PATH"
  else
    echo "❌ ERROR: Traefik ACME storage exists at $ACME_PATH but is not readable by $(id -un)." >&2
    exit 1
  fi
else
  if [[ -r "$SYS_ACME" ]]; then
    cp "$SYS_ACME" "$ACME_PATH"
    chmod 600 "$ACME_PATH" >/dev/null 2>&1 || true
    echo "🔐 Copied system ACME storage to user scope: $ACME_PATH"
  else
    printf '{}' > "$ACME_PATH"
    chmod 600 "$ACME_PATH" >/dev/null 2>&1 || true
    echo "🆕 Created new ACME storage at $ACME_PATH (600)"
  fi
fi

# Ensure certificatesResolvers.letsencrypt exists in user config with a concrete email value
EMAIL="${TRAEFIK_EMAIL:-}"
if [ -n "$EMAIL" ] && [ -f "$CONFIG_PATH" ]; then
  if ! grep -q "certificatesResolvers:" "$CONFIG_PATH"; then
    cat >>"$CONFIG_PATH" <<EOF
certificatesResolvers:
  letsencrypt:
    acme:
      email: "$EMAIL"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF
  else
    if grep -q "email:.*\${TRAEFIK_EMAIL" "$CONFIG_PATH"; then
      if command -v sed >/dev/null 2>&1; then
        sed -i.bak -E "s#email:[[:space:]]*\"?\\\${TRAEFIK_EMAIL[^\"}]*\"?#email: \"$EMAIL\"#" "$CONFIG_PATH" || true
      fi
    fi
  fi
fi

if [ "${TRAEFIK_PING_ENABLED:-true}" = "true" ]; then
  if ! grep -q 'ping:' "$CONFIG_PATH"; then
    cat >>"$CONFIG_PATH" <<'YAML'
ping:
  entryPoint: web
YAML
  fi
fi


