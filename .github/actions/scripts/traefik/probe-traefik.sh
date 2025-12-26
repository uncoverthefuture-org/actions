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

# Probe tuning knobs (overridable via environment)
# - PROBE_TRIES:   number of attempts before failing (default 12)
# - PROBE_DELAY:   delay between attempts in seconds (default 5)
# - PROBE_TIMEOUT: per-attempt curl timeout in seconds (default 8)
# - PROBE_HTTP_FALLBACK: when true, try HTTP after HTTPS fails (default true)
PROBE_TRIES="${PROBE_TRIES:-12}"
PROBE_DELAY="${PROBE_DELAY:-5}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-8}"
PROBE_HTTP_FALLBACK="${PROBE_HTTP_FALLBACK:-true}"

log() { printf '%s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }
notice() { printf 'ℹ️  %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found"; exit 1; }
}

emit_repair_suggestion() {
  local type="${1:-}" # 'acme_missing', 'acme_perms', 'tls_fail', 'ufw_fail'
  
  echo "================================================================"
  echo "🛠️  RECOMMENDED REPAIR STEPS"
  echo "================================================================"
  case "$type" in
    acme_missing|acme_perms)
      echo "It looks like Traefik's certificate storage (acme.json) is missing or misconfigured."
      echo "Run these commands on the server to fix it:"
      echo ""
      echo "  mkdir -p ~/.local/share/traefik"
      echo "  touch ~/.local/share/traefik/acme.json"
      echo "  chmod 600 ~/.local/share/traefik/acme.json"
      echo "  systemctl --user restart traefik.service"
      ;;
    tls_fail|tls_reset)
      echo "HTTPS is reachable but the certificate is invalid or not yet issued."
      echo "If issuance is stuck, you can force a reset of Let's Encrypt data:"
      echo ""
      echo "  # ⚠️ This will delete all cached certificates and request new ones"
      echo "  mv ~/.local/share/traefik/acme.json ~/.local/share/traefik/acme.json.bak"
      echo "  systemctl --user restart traefik.service"
      echo ""
      echo "Alternatively, re-run deployment with: traefik_reset_acme: 'true'"
      ;;
    ufw_fail)
      echo "External access to port 443 (HTTPS) appears to be blocked by a firewall."
      echo "Run this to ensure UFW allows HTTPS traffic:"
      echo ""
      echo "  sudo ufw allow 443/tcp"
      echo "  sudo ufw reload"
      ;;
    *)
      echo "General Traefik health issues detected."
      echo "Check service status and logs:"
      echo ""
      echo "  systemctl --user status traefik.service"
      echo "  podman logs traefik"
      ;;
  esac
  echo "================================================================"
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

  notice "Verifying ACME storage for certificates ..."
  local acme_file="$HOME/.local/share/traefik/acme.json"
  if [ ! -f "$acme_file" ]; then
    # In Quadlet mode, the container unit has a mount for this file.
    # If it's missing, the service will fail with "no such file or directory".
    notice "⚠️  ACME storage file $acme_file not found."
    emit_repair_suggestion "acme_missing"
  else
    local perm=$(stat -c '%a' "$acme_file" 2>/dev/null || echo "unknown")
    if [ "$perm" != "600" ]; then
      notice "⚠️  ACME storage file has insecure permissions ($perm); expected 600."
      emit_repair_suggestion "acme_perms"
    else
      notice "✅ ACME storage file exists with correct permissions (600)"
    fi
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

check_network_cohesion() {
  # Validate that both Traefik and app container are on the same Podman network.
  # This check ensures routing can work between containers.
  # NOTE: Added to support task "Validate both Traefik and app are attached to the same Podman network"
  # from traefik-domain-routing-not-reaching-container.md plan.
  local app_container="${1:-}"
  local network_name="${2:-traefik-network}"
  
  if [ -z "$app_container" ]; then
    notice "Network cohesion check: app container name not provided (skipping)"
    return 0
  fi
  
  if ! command -v podman >/dev/null 2>&1; then
    notice "Network cohesion check: podman not available (skipping)"
    return 0
  fi
  
  # Get networks for both containers
  local traefik_nets app_nets
  traefik_nets=$(podman inspect -f '{{ range $k := .NetworkSettings.Networks }}{{ $k }} {{ end }}' traefik 2>/dev/null || echo "")
  app_nets=$(podman inspect -f '{{ range $k := .NetworkSettings.Networks }}{{ $k }} {{ end }}' "$app_container" 2>/dev/null || echo "")
  
  if [ -z "$traefik_nets" ]; then
    err "Traefik container not found or has no networks"
    return 1
  fi
  
  if [ -z "$app_nets" ]; then
    err "App container '$app_container' not found or has no networks"
    return 1
  fi
  
  # Check if both are on the target network
  if printf '%s' "$traefik_nets" | grep -qw "$network_name" && printf '%s' "$app_nets" | grep -qw "$network_name"; then
    log "✅ Network cohesion OK: both containers on $network_name"
    return 0
  else
    err "Network mismatch: traefik on [$traefik_nets], app on [$app_nets], expected both on $network_name"
    return 1
  fi
}

post() {
  local router="$ROUTER_NAME" domain="$DOMAIN" port="$SERVICE_PORT" path="$PROBE_PATH"
  if [ -z "$domain" ]; then
    err "Domain is required for post-deploy probe"
    exit 4
  fi
  require_cmd curl

  # DNS resolution hint before probing to surface misconfigured records early
  if command -v getent >/dev/null 2>&1; then
    resolved_ips=$(getent hosts "$domain" | awk '{print $1}' | tr '\n' ' ' | sed 's/ *$//')
  elif command -v dig >/dev/null 2>&1; then
    resolved_ips=$(dig +short "$domain" | tr '\n' ' ' | sed 's/ *$//')
  elif command -v nslookup >/dev/null 2>&1; then
    resolved_ips=$(nslookup "$domain" 2>/dev/null | awk '/^Address: /{print $2}' | tr '\n' ' ' | sed 's/ *$//')
  else
    resolved_ips=""
  fi
  if [ -n "$resolved_ips" ]; then
    notice "DNS: $domain → $resolved_ips"
  else
    notice "DNS: $domain did not resolve (continuing; network probe may time out)"
  fi

  local tries="$PROBE_TRIES" delay="$PROBE_DELAY" timeout="$PROBE_TIMEOUT" i=1 code=""

  # First, attempt a strict TLS request without -k to catch cert errors early
  if [ "${CERT_VALIDATE:-true}" = "true" ]; then
    if ! curl -fsS -o /dev/null --max-time "$timeout" "https://$domain$path" 2>/dev/null; then
      notice "TLS validation failed for https://$domain$path (certificate not trusted yet)."
      notice "Hints: ensure TRAEFIK_ENABLE_ACME=true and TRAEFIK_EMAIL is set; include both apex and www hosts; wait up to a minute for issuance."
      emit_repair_suggestion "tls_fail"
    else
      notice "TLS validation OK for https://$domain$path"
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    notice "Inspecting TLS certificate for $domain:443 ..."
    cert_info=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null || true)
    if [ -n "$cert_info" ]; then
      issuer=$(printf '%s\n' "$cert_info" | sed -n 's/^issuer=//p' | head -n1)
      subject=$(printf '%s\n' "$cert_info" | sed -n 's/^subject=//p' | head -n1)
      not_before=$(printf '%s\n' "$cert_info" | sed -n 's/^notBefore=//p' | head -n1)
      not_after=$(printf '%s\n' "$cert_info" | sed -n 's/^notAfter=//p' | head -n1)
      if [ -n "$issuer" ]; then
        notice "TLS cert issuer: $issuer"
      fi
      if [ -n "$subject" ]; then
        notice "TLS cert subject: $subject"
      fi
      if [ -n "$not_before" ] && [ -n "$not_after" ]; then
        notice "TLS cert validity: notBefore=$not_before, notAfter=$not_after"
      fi
      if printf '%s\n' "$issuer" | grep -qi 'Fake LE Intermediate'; then
        notice "TLS inspection: certificate appears to be a Let's Encrypt staging certificate. Browsers will not trust this."
        notice "To rotate to a production certificate, reset the Traefik ACME storage (for example remove ~/.local/share/traefik/acme.json) or set TRAEFIK_RESET_ACME=true (traefik_reset_acme: 'true') on the next deployment."
      fi
    else
      notice "TLS inspection: unable to retrieve certificate details via openssl."
    fi
  else
    notice "TLS inspection: openssl not available on host; skipping certificate inspection."
  fi

  notice "Probing https://$domain$path via Traefik (up to $tries tries) ..."
  while [ $i -le $tries ]; do
    code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time "$timeout" "https://$domain$path" || echo "000")
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
      log "✅ Domain probe succeeded (HTTPS, HTTP $code)"
      return 0
    fi
    notice "Attempt $i/$tries: got HTTP $code; retrying in ${delay}s ..."
    sleep "$delay"
    i=$((i+1))
  done

  # Optional HTTP fallback (useful when ACME/TLS is not yet provisioned or disabled)
  if [ "${PROBE_HTTP_FALLBACK,,}" = "true" ]; then
    i=1; code=""
    notice "HTTPS probe failed; trying HTTP fallback to http://$domain$path (up to $tries tries) ..."
    while [ $i -le $tries ]; do
      code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "$timeout" "http://$domain$path" || echo "000")
      if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        log "✅ Domain probe succeeded (HTTP, HTTP $code)"
        return 0
      fi
      notice "Attempt $i/$tries: got HTTP $code; retrying in ${delay}s ..."
      sleep "$delay"
      i=$((i+1))
    done
  fi

  # Identify likely cause for specific repair suggestion
  local cause="general"
  if [[ "$code" == "000" ]]; then
    cause="ufw_fail" # Timeout usually implies firewall
  elif [[ "$code" == "404" ]]; then
    cause="tls_reset" # 404 might mean router exists but backend is bad or cert is not showing
  fi

  err "Domain probe failed after $tries attempts (last HTTP $code)"
  emit_repair_suggestion "$cause"
  notice "--- Probe Summary ---"
  notice "URL: https://$domain$path"
  notice "Tries: $tries, Delay: ${delay}s, Last code: $code"
  if [ -n "$router" ]; then
    notice "Router: $router (declared service port: $port)"
  fi
  if command -v podman >/dev/null 2>&1; then
    app_cid=""; app_name=""; label_port=""
    for cid in $(podman ps -aq 2>/dev/null); do
      val=$(podman inspect -f '{{ index .Config.Labels "traefik.http.services.'"$router"'.loadbalancer.server.port" }}' "$cid" 2>/dev/null || true)
      if [ -n "$val" ]; then app_cid="$cid"; label_port="$val"; break; fi
    done
    if [ -n "$label_port" ]; then
      notice "Detected label service port: $label_port"
    fi
    if [ -n "$app_cid" ]; then
      app_name=$(podman inspect -f '{{.Name}}' "$app_cid" 2>/dev/null | sed 's,^/,,')
      app_nets=$(podman inspect -f '{{ range $k := .NetworkSettings.Networks }}{{ $k }} {{ end }}' "$app_cid" 2>/dev/null || echo "")
      traefik_nets=$(podman inspect -f '{{ range $k := .NetworkSettings.Networks }}{{ $k }} {{ end }}' traefik 2>/dev/null || echo "")
      notice "App container: ${app_name:-unknown}"
      notice "Networks: app=[$app_nets] traefik=[$traefik_nets]"
    fi
  fi
  notice "--- Recent Traefik logs ---"
  if command -v podman >/dev/null 2>&1; then
    podman logs --tail=120 traefik 2>/dev/null || true
  else
    notice "Traefik logs unavailable (podman not installed)"
  fi
  notice "--- Next steps ---"
  notice "1) Ensure the app listens on the advertised port and on 0.0.0.0 (not 127.0.0.1)."
  notice "   - If needed, set container_port input or WEB_CONTAINER_PORT/TARGET_PORT/PORT in .env"
  notice "2) Verify both containers share a network (e.g., traefik-network)."
  notice "   - podman inspect traefik | grep -A2 Networks; podman inspect <app> | grep -A2 Networks"
  notice "3) If your health path is not '/', set probe_path accordingly."
  exit 4
}

case "$MODE" in
  preflight) preflight ;;
  post) post ;;
  *) err "Usage: $0 preflight | post <router> <domain> <service_port>"; exit 1 ;;
 esac
