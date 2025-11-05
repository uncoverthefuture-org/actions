#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${DIAG_DOMAIN:-}"
APP_CTN="${DIAG_APP_CONTAINER:-}"
TRAEFIK_CTN="${DIAG_TRAEFIK_CONTAINER:-traefik}"
HOST_PORT="${DIAG_HOST_PORT:-8080}"
CONT_PORT="${DIAG_CONTAINER_PORT:-3000}"
TIMEOUT=7

has() { command -v "$1" >/dev/null 2>&1; }
say() { echo "$*"; }
sec() { echo; echo "==== $* ===="; }

LOG="/tmp/uactions_diag_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
ln -sf "$LOG" /tmp/uactions_diag_latest.log 2>/dev/null || true

START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
say "uactions routing diagnostics | $START_TS UTC"
sec "Environment"
( whoami || true )
( uname -a || true )
( hostname -f 2>/dev/null || hostname || true )
( grep VERSION= /etc/os-release 2>/dev/null || true )

PUB_IP=""
if has curl; then
  for url in "https://api.ipify.org" "https://ifconfig.co" "https://checkip.amazonaws.com"; do
    v=$(curl -fsS --max-time 3 "$url" 2>/dev/null || true)
    v=$(echo "$v" | tr -d '\r')
    if [ -n "$v" ]; then PUB_IP="$v"; break; fi
  done
fi
say "Public IP: ${PUB_IP:-unknown}"

sec "Tooling"
for cmd in curl ss netstat ufw firewall-cmd iptables nft podman docker openssl dig host getent; do
  if has "$cmd"; then echo "- $cmd: OK"; else echo "- $cmd: missing"; fi
done

sec "DNS"
A_REC=""
if [ -n "$DOMAIN" ]; then
  if has dig; then
    echo "dig A $DOMAIN"
    dig +short A "$DOMAIN" || true
    echo "dig AAAA $DOMAIN"
    dig +short AAAA "$DOMAIN" || true
    A_REC=$(dig +short A "$DOMAIN" | head -n1 || true)
  elif has host; then
    host "$DOMAIN" || true
    A_REC=$(host -t A "$DOMAIN" 2>/dev/null | awk '/has address/ {print $4; exit}' || true)
  else
    getent ahostsv4 "$DOMAIN" 2>/dev/null || true
    A_REC=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
  fi
  echo "Resolved A: ${A_REC:-none}"
  if [ -n "$PUB_IP" ] && [ -n "$A_REC" ]; then
    if [ "$A_REC" = "$PUB_IP" ]; then echo "DNS match: OK"; else echo "DNS match: MISMATCH ($A_REC vs $PUB_IP)"; fi
  fi
else
  echo "No domain provided"
fi

sec "Listeners 80/443"
if has ss; then
  ss -ltnp 2>/dev/null | grep -E ":80 |:443 " || true
elif has netstat; then
  netstat -plnt 2>/dev/null | grep -E ":80 |:443 " || true
fi
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet nginx && echo "nginx: ACTIVE" || echo "nginx: inactive"
  systemctl is-active --quiet apache2 && echo "apache2: ACTIVE" || echo "apache2: inactive"
fi

sec "Firewall"
if has ufw; then ( ufw status verbose || true ); fi
if has firewall-cmd; then ( firewall-cmd --state || true ); ( firewall-cmd --list-all || true ); fi
if has nft; then ( nft list ruleset 2>/dev/null | sed -n '1,150p' || true ); fi
if has iptables; then ( iptables -S 2>/dev/null | sed -n '1,150p' || true ); fi

sec "Container runtime"
RUNTIME=""
if has podman; then RUNTIME="podman"; elif has docker; then RUNTIME="docker"; fi
if [ -n "$RUNTIME" ]; then
  ($RUNTIME version || true)
  $RUNTIME ps --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
else
  echo "No podman/docker"
fi

sec "Traefik"
if [ -n "$RUNTIME" ] && [ -n "$TRAEFIK_CTN" ]; then
  if $RUNTIME inspect "$TRAEFIK_CTN" >/dev/null 2>&1; then
    echo "traefik container present"
    $RUNTIME port "$TRAEFIK_CTN" || true
    $RUNTIME inspect --format 'Networks: {{range $k,$v := .NetworkSettings.Networks}}{{printf "%s " $k}}{{end}}' "$TRAEFIK_CTN" || true
    $RUNTIME logs --tail 120 "$TRAEFIK_CTN" 2>/dev/null || true
  else
    echo "traefik container missing"
  fi
fi

sec "App container"
if [ -n "$RUNTIME" ] && [ -n "$APP_CTN" ]; then
  if $RUNTIME inspect "$APP_CTN" >/dev/null 2>&1; then
    echo "app container present"
    $RUNTIME inspect --format 'State: {{.State.Status}} (Started: {{.State.StartedAt}})' "$APP_CTN" || true
    $RUNTIME port "$APP_CTN" || true
    echo "labels (traefik.*):"
    $RUNTIME inspect --format '{{range $k,$v := .Config.Labels}}{{printf "%s=%s\n" $k $v}}{{end}}' "$APP_CTN" 2>/dev/null | grep -i '^traefik\.' || true
    echo "networks:"
    $RUNTIME inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{printf "%s " $k}}{{end}}' "$APP_CTN" || true
    echo "in-container listeners:"
    $RUNTIME exec "$APP_CTN" sh -lc 'ss -ltnp 2>/dev/null | head -n 60 || netstat -ltnp 2>/dev/null | head -n 60' 2>/dev/null || true
    echo "recent logs:"
    $RUNTIME logs --tail 80 "$APP_CTN" 2>/dev/null || true
  else
    echo "app container missing"
  fi
fi

sec "HTTP"
if [ -n "$DOMAIN" ] && has curl; then
  echo "curl -I http://$DOMAIN"
  (curl -I --max-time "$TIMEOUT" -sS "http://$DOMAIN" || true)
  echo "curl -I https://$DOMAIN"
  (curl -I -k --max-time "$TIMEOUT" -sS "https://$DOMAIN" || true)
  if [ -n "$PUB_IP" ]; then
    echo "curl --resolve http"
    (curl -I --max-time "$TIMEOUT" --resolve "$DOMAIN:80:$PUB_IP" -sS "http://$DOMAIN" || true)
    echo "curl --resolve https"
    (curl -I -k --max-time "$TIMEOUT" --resolve "$DOMAIN:443:$PUB_IP" -sS "https://$DOMAIN" || true)
  fi
fi
if has curl; then
  echo "curl -s http://127.0.0.1:$HOST_PORT"
  (curl -sS -o /dev/null -w '%{http_code}\n' --max-time "$TIMEOUT" "http://127.0.0.1:$HOST_PORT" || true)
fi
if [ -n "$RUNTIME" ] && [ -n "$APP_CTN" ]; then
  echo "in-container http probe"
  $RUNTIME exec "$APP_CTN" sh -lc "if command -v curl >/dev/null 2>&1; then curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:${CONT_PORT} --max-time ${TIMEOUT}; elif command -v wget >/dev/null 2>&1; then wget -qO- --server-response http://127.0.0.1:${CONT_PORT} 2>&1 | awk '/HTTP\//{print \$2; exit}'; else echo NO_CURL_WGET; fi" 2>/dev/null || true
fi

DNS_OK="unknown"
if [ -n "$PUB_IP" ] && [ -n "$A_REC" ]; then
  if [ "$PUB_IP" = "$A_REC" ]; then DNS_OK="OK"; else DNS_OK="mismatch"; fi
fi
L80=$( (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null || true) | grep -E 'LISTEN' | grep -E '(:|\.)80 ' || true )
L443=$( (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null || true) | grep -E 'LISTEN' | grep -E '(:|\.)443 ' || true )
LISTEN_OK="FAIL"; if [ -n "$L80$L443" ]; then LISTEN_OK="OK"; fi
TRAEFIK_OK="unknown"; if [ -n "$RUNTIME" ] && [ -n "$TRAEFIK_CTN" ] && $RUNTIME inspect "$TRAEFIK_CTN" >/dev/null 2>&1; then TRAEFIK_OK="OK"; else TRAEFIK_OK="FAIL"; fi
APP_OK="unknown"; if [ -n "$RUNTIME" ] && [ -n "$APP_CTN" ] && $RUNTIME inspect "$APP_CTN" >/dev/null 2>&1; then APP_OK="OK"; else APP_OK="FAIL"; fi

sec "Summary"
printf "%-32s %s\n" "DNS matches server IP:" "$DNS_OK"
printf "%-32s %s\n" "80/443 listeners:" "$LISTEN_OK"
printf "%-32s %s\n" "Traefik container:" "$TRAEFIK_OK"
printf "%-32s %s\n" "App container:" "$APP_OK"
echo "Log: $LOG"
