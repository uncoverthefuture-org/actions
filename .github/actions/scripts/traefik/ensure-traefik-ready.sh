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
TRAEFIK_MODE="${TRAEFIK_MODE:-container}"

# Track whether the ping endpoint responds so we can reconcile when legacy
# deployments reused without the ping flag enabled still return HTTP 404.
PING_REACHABILITY="unknown"
PING_RESTART_ATTEMPTED="false"

dump_traefik_logs() {
  if command -v podman >/dev/null 2>&1; then
    echo "🔎 podman ps --filter name=traefik"
    podman ps --filter name=traefik || true
    echo "📜 podman logs --tail=120 traefik"
    podman logs --tail=120 traefik 2>/dev/null || true
  fi
}

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
QUADLET_INSTALL="$SCRIPT_DIR/install-quadlet-sockets.sh"

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
      PING_REACHABILITY="fail"
      # Use -sS (not -f) and ignore curl's exit code so that HTTP 4xx responses
      # still produce a valid status code (e.g. 404) without appending extra
      # digits like "404000". Any 2xx-4xx result is treated as reachable.
      code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "http://127.0.0.1/ping" || true)
      if [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
        notice "Traefik ping reachable on http://127.0.0.1/ping (HTTP $code)"
        PING_REACHABILITY="ok"
      else
        notice "Traefik ping not reachable on http://127.0.0.1/ping (HTTP $code)"
        PING_REACHABILITY="fail:$code"
      fi
    fi

    modes=",${DASHBOARD_PUBLISH_MODES:-},"
    if printf '%s' "$modes" | grep -q ',http8080,'; then
      # Same fix as above: drop -f and avoid concatenating fallback output so
      # that 404 and other HTTP errors are reported as-is.
      code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "${PROBE_TIMEOUT:-6}" "http://127.0.0.1:8080/api/overview" || true)
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
  if [ "$TRAEFIK_MODE" != "quadlet" ]; then
    # Container-managed path: reconcile configuration even when healthy;
    # setup-traefik.sh performs a fast path when confighash matches and avoids
    # unnecessary restarts.
    if ! "$SETUP"; then
      echo "::error::Traefik setup reconciliation failed; see logs above." >&2
      dump_traefik_logs
      exit 1
    fi
    # Verify again after potential reconciliation
    if ! probe_preflight; then
      echo "::error::Traefik preflight failed immediately after reconciliation." >&2
      dump_traefik_logs
      exit 1
    fi
  else
    # Quadlet-managed path: assert that the quadlet units match our desired
    # configuration by re-running install-quadlet-sockets.sh when available,
    # then verifying listeners again.
    if [ -x "$QUADLET_INSTALL" ]; then
      echo "🛠 Reconciling Quadlet Traefik units via install-quadlet-sockets.sh ..."
      if ! "$QUADLET_INSTALL"; then
        echo "::error::Quadlet Traefik installation failed; see logs above." >&2
        dump_traefik_logs
        exit 1
      fi
      if ! probe_preflight; then
        echo "::error::Traefik preflight failed immediately after Quadlet reconciliation." >&2
        dump_traefik_logs
        exit 1
      fi
    else
      echo "::notice::TRAEFIK_MODE=quadlet but install-quadlet-sockets.sh not found; skipping Quadlet reconciliation and relying on existing units."
    fi
  fi
  check_local_reachability || true
  if [ "${TRAEFIK_PING_ENABLED:-true}" = "true" ] && [[ "$PING_REACHABILITY" != ok ]]; then
    if [ "$TRAEFIK_MODE" != "quadlet" ]; then
      if [ "$PING_RESTART_ATTEMPTED" != "true" ]; then
        notice "Traefik ping endpoint still missing; forcing one-time restart to apply ping settings."
        PING_RESTART_ATTEMPTED="true"
        if ! TRAEFIK_FORCE_RESTART=true "$SETUP"; then
          echo "::error::Traefik forced restart failed; see logs above." >&2
          dump_traefik_logs
          exit 1
        fi
        if ! probe_preflight; then
          echo "::error::Traefik preflight failed after forced restart." >&2
          dump_traefik_logs
          exit 1
        fi
        check_local_reachability || true
      fi
      if [[ "$PING_REACHABILITY" != ok ]]; then
        echo "::error::Traefik ping endpoint remains unreachable after forced restart." >&2
        dump_traefik_logs
        exit 1
      fi
    else
      # Quadlet mode: best-effort user-level restart of traefik.service if the
      # ping endpoint remains unreachable after unit reconciliation.
      if [ "$PING_RESTART_ATTEMPTED" != "true" ] && command -v systemctl >/dev/null 2>&1; then
        notice "Traefik ping not reachable; attempting systemd --user restart of traefik.service (Quadlet mode)."
        PING_RESTART_ATTEMPTED="true"
        systemctl --user restart traefik.service >/dev/null 2>&1 || true
        if ! probe_preflight; then
          echo "::error::Traefik preflight failed after Quadlet service restart." >&2
          dump_traefik_logs
          exit 1
        fi
        check_local_reachability || true
      fi
      if [[ "$PING_REACHABILITY" != ok ]]; then
        echo "::error::Traefik ping endpoint remains unreachable after Quadlet reconciliation/restart." >&2
        dump_traefik_logs
        exit 1
      fi
    fi
  fi
  check_ip_reachability || true
  exit 0
fi

# Slow path: reconcile then verify (container-managed and Quadlet Traefik)
if [ "$TRAEFIK_MODE" != "quadlet" ]; then
  reconcile_setup
else
  if [ -x "$QUADLET_INSTALL" ]; then
    echo "🛠 Reconciling Traefik via Quadlet installer (slow path) ..."
    if ! "$QUADLET_INSTALL"; then
      echo "::error::Quadlet Traefik installation failed in slow-path reconciliation; see logs above." >&2
      dump_traefik_logs
      exit 1
    fi
  fi
fi

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
