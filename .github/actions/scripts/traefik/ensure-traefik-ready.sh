#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# ensure-traefik-ready.sh - Idempotent Traefik preflight + reconciliation
# ----------------------------------------------------------------------------
# Purpose:
#   - Fast-path: if Traefik is already healthy (ports 80/443 listening), exit 0
#   - Slow-path: reconcile by invoking setup-traefik.sh, then verify again
#   - Optional reachability checks via localhost and host IP, including dashboard
#
# Inputs (environment variables):
#   ENSURE_TRAEFIK          - Gate for all checks (default: true)
#   TRAEFIK_ENABLED         - Whether app routing via Traefik is desired (true/false)
#   TRAEFIK_EMAIL           - ACME email (required when ACME enabled)
#   TRAEFIK_ENABLE_ACME     - Enable ACME in setup (default: true)
#   TRAEFIK_PING_ENABLED    - Enable ping endpoint (default: true)
#   TRAEFIK_DASHBOARD       - Deprecated dashboard flag (prefer publish modes)
#   DASHBOARD_PUBLISH_MODES - CSV: http8080, https8080, subdomain, or both
#   DASHBOARD_HOST          - FQDN for subdomain dashboard mode
#   PROBE_TRIES/DELAY/TIMEOUT/HTTP_FALLBACK - tuning for probes
# ----------------------------------------------------------------------------
set -euo pipefail

if [ "${DEBUG:-false}" = "true" ]; then set -x; fi

ENSURE_TRAEFIK="${ENSURE_TRAEFIK:-true}"
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"

if [ "$TRAEFIK_ENABLED" != "true" ] || [ "${ENSURE_TRAEFIK}" != "true" ]; then
  echo "::notice::Traefik ensure skipped (TRAEFIK_ENABLED=$TRAEFIK_ENABLED, ENSURE_TRAEFIK=$ENSURE_TRAEFIK)"
  exit 0
fi

# Guidance when ACME is requested without an email (common cause of TLS issues)
if [ "${TRAEFIK_ENABLE_ACME:-true}" = "true" ] && [ -z "${TRAEFIK_EMAIL:-}" ]; then
  echo "::warning::TRAEFIK_ENABLE_ACME=true but TRAEFIK_EMAIL is empty."
  echo "           Set TRAEFIK_EMAIL to a valid address to allow Let's Encrypt issuance."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/probe-traefik.sh"
SETUP="$SCRIPT_DIR/setup-traefik.sh"

# Local helpers
notice() { printf 'ℹ️  %s\n' "$*"; }
log() { printf '%s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }

probe_preflight() {
  if "$PROBE" preflight; then
    return 0
  fi
  return 1
}

check_local_reachability() {
  # Optional localhost reachability checks
  # - Ping endpoint (if enabled) on http://127.0.0.1/ping
  # - Dashboard/API on http://127.0.0.1:8080 if published locally
  if command -v curl >/dev/null 2>&1; then
    if [ "${TRAEFIK_PING_ENABLED:-true}" = "true" ]; then
      code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "http://127.0.0.1/ping" || echo "000")
      if [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
        notice "Traefik ping reachable on http://127.0.0.1/ping (HTTP $code)"
      else
        notice "Traefik ping not reachable on http://127.0.0.1/ping (HTTP $code)"
      fi
    fi

    modes=",${DASHBOARD_PUBLISH_MODES:-},"
    if printf '%s' "$modes" | grep -q ',http8080,'; then
      code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "http://127.0.0.1:8080/api/overview" || echo "000")
      if [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
        notice "Traefik API reachable at http://127.0.0.1:8080/api/overview (HTTP $code)"
      else
        notice "Traefik API not reachable at http://127.0.0.1:8080 (HTTP $code)"
      fi
    fi
  fi
}

check_ip_reachability() {
  # Probe via the host IP to assert listeners are externally reachable.
  # We accept any HTTP status (including 404/401) as a sign that Traefik responded.
  # Uses -k for HTTPS to ignore certificate/domain mismatch.
  local ip=""
  if command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  fi
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)
  fi
  if [ -z "$ip" ]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "http://$ip/" || echo "000")
    notice "Host IP HTTP probe ($ip): HTTP $code"
    code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "https://$ip/" || echo "000")
    notice "Host IP HTTPS probe ($ip): HTTP $code"
  fi
}

reconcile_setup() {
  echo "================================================================"
  echo "🛠 Reconciling Traefik runtime (starting or replacing container) ..."
  echo "================================================================"
  # Best-effort removal (setup-traefik uses --replace as well)
  if command -v podman >/dev/null 2>&1 && podman container exists traefik >/dev/null 2>&1; then
    podman rm -f traefik >/dev/null 2>&1 || true
  fi
  "$SETUP"
}

# Fast path
echo "================================================================"
echo "🔍 Traefik preflight"
echo "================================================================"
if probe_preflight; then
  echo "✅ Traefik preflight OK (listeners on 80/443)"
  # Reconcile configuration even when healthy; setup-traefik.sh performs a fast
  # path when confighash matches and avoids unnecessary restarts.
  "$SETUP" || true
  # Verify again after potential reconciliation
  probe_preflight || true
  check_local_reachability || true
  check_ip_reachability || true
  exit 0
fi

# Slow path: reconcile then verify
reconcile_setup

echo "================================================================"
echo "🔁 Verifying Traefik after reconciliation"
echo "================================================================"
if probe_preflight; then
  echo "✅ Traefik is ready after reconciliation"
  check_local_reachability || true
  check_ip_reachability || true
  exit 0
fi

err "Traefik reconciliation failed; listeners on 80/443 not healthy after setup"
if command -v podman >/dev/null 2>&1; then
  podman ps --filter name=traefik || true
  podman logs --tail=120 traefik 2>/dev/null || true
fi
exit 1
