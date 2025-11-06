#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# probe-traefik.sh - Health and routing probes for Traefik on a remote host
# ----------------------------------------------------------------------------
# Purpose:
#   Perform preflight and post-deploy checks for Traefik. Designed to be run
#   over SSH by composite actions. Emits clear errors and non-zero exit codes
#   so CI fails fast when Traefik or routing is unhealthy.
#
# Usage:
#   probe-traefik.sh preflight
#   probe-traefik.sh post <router_name> <domain> <service_port>
#
# Exit codes:
#   0 - Success
#   1 - Traefik container not running
#   2 - Ports 80/443 not listening
#   3 - Traefik API probe failed (optional check)
#   4 - Domain probe failed after retries
# ----------------------------------------------------------------------------
set -euo pipefail

MODE="${1:-}"
ROUTER_NAME="${2:-}"
DOMAIN="${3:-}"
SERVICE_PORT="${4:-}"
PROBE_PATH="${5:-/}"

case "$PROBE_PATH" in
  "") PROBE_PATH="/" ;;
  /*) ;;
  *) PROBE_PATH="/$PROBE_PATH" ;;
esac

log() { printf '%s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }
notice() { printf 'ℹ️  %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found"; exit 1; }
}

# Prefer ss, fallback to netstat
have_ss=false
if command -v ss >/dev/null 2>&1; then have_ss=true; fi

check_listeners_80_443() {
  if $have_ss; then
    local out
    out=$(ss -ltn 2>/dev/null || true)
    if ! printf '%s' "$out" | grep -qE '[:\[]80\b'; then return 1; fi
    if ! printf '%s' "$out" | grep -qE '[:\[]443\b'; then return 1; fi
    return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    local out
    out=$(netstat -ltn 2>/dev/null || true)
    printf '%s' "$out" | grep -qE '[:\[]80\b' && printf '%s' "$out" | grep -qE '[:\[]443\b'
    return $?
  fi
  # As a last resort, assume listeners unknown (treat as failure)
  return 1
}

preflight() {
  notice "Checking Traefik container status ..."
  local has_podman=false has_container=false st="unknown" sockets_active=false
  if command -v podman >/dev/null 2>&1; then has_podman=true; fi
  if $has_podman && podman container exists traefik >/dev/null 2>&1; then
    has_container=true
    st=$(podman inspect -f '{{.State.Status}}' traefik 2>/dev/null || echo unknown)
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active --quiet http.socket 2>/dev/null && \
       systemctl --user is-active --quiet https.socket 2>/dev/null; then
      sockets_active=true
    fi
  fi
  if [ "$has_container" = "true" ]; then
    if [ "$st" != "running" ] && [ "$sockets_active" != "true" ]; then
      err "Traefik is not running (status: $st) and socket-activation not detected"
      $has_podman && podman ps --filter name=traefik || true
      $has_podman && podman logs --tail=80 traefik 2>/dev/null || true
      exit 1
    fi
    if [ "$st" != "running" ] && [ "$sockets_active" = "true" ]; then
      notice "Traefik container not running, but systemd sockets are active (quadlet mode)."
    fi
  else
    if [ "$sockets_active" = "true" ]; then
      notice "Traefik container absent but systemd sockets are active (quadlet mode)."
    else
      notice "Traefik container not found and sockets inactive; verifying listeners regardless ..."
    fi
  fi

  notice "Verifying listeners on 80/443 ..."
  if ! check_listeners_80_443; then
    err "Ports 80/443 are not listening"
    ss -ltn 2>/dev/null | head -n 80 || netstat -ltn 2>/dev/null | head -n 80 || true
    exit 2
  fi

  # Optional API probe if dashboard/API is exposed locally
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 3 http://127.0.0.1:8080/api/overview >/dev/null 2>&1; then
      notice "Traefik API reachable on 127.0.0.1:8080"
      curl -fsS --max-time 3 http://127.0.0.1:8080/api/entrypoints >/dev/null 2>&1 || true
    else
      notice "Traefik API not reachable (skipping non-fatal check)"
    fi
  fi

  log "✅ Preflight OK"
}

post() {
  local router="$ROUTER_NAME" domain="$DOMAIN" port="$SERVICE_PORT" path="$PROBE_PATH"
  if [ -z "$domain" ]; then
    err "Domain is required for post-deploy probe"
    exit 4
  fi
  require_cmd curl

  local tries=12 delay=5 i=1 code=""
  notice "Probing https://$domain$path via Traefik (up to $tries tries) ..."
  while [ $i -le $tries ]; do
    code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 8 "https://$domain$path" || echo "000")
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
      log "✅ Domain probe succeeded (HTTP $code)"
      return 0
    fi
    notice "Attempt $i/$tries: got HTTP $code; retrying in ${delay}s ..."
    sleep "$delay"
    i=$((i+1))
  done

  err "Domain probe failed after $tries attempts (last HTTP $code)"
  if command -v podman >/dev/null 2>&1; then
    notice "Recent Traefik logs:"
    podman logs --tail=120 traefik 2>/dev/null || true
  else
    notice "Traefik logs unavailable (podman not installed)"
  fi
  if [ -n "$router" ]; then
    notice "Router hint: $router (service port $port)"
  fi
  exit 4
}

case "$MODE" in
  preflight) preflight ;;
  post) post ;;
  *) err "Usage: $0 preflight | post <router> <domain> <service_port>"; exit 1 ;;
 esac
