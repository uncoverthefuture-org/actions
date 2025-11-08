#!/usr/bin/env bash
# build-traefik-labels.sh
# Echo Traefik --label args for a single app router/service based on inputs.
# Usage:
#   ENV-based: set ROUTER_NAME, DOMAIN, CONTAINER_PORT, ENABLE_ACME(true|false), RESOLVER_NAME(optional)
#   Args-based: build-traefik-labels.sh <router_name> <domain> <container_port> [enable_acme]
# Output:
#   Lines suitable for command substitution or mapfile, e.g.:
#     mapfile -t LABEL_ARGS < <(/path/build-traefik-labels.sh ...)
#     podman run ... "${LABEL_ARGS[@]}"

# Notes:
# - Host rule values use double quotes (e.g., Host("a") || Host("b")) to avoid shell backtick evaluation.
# - When ACME is disabled, TLS labels are omitted and the primary router uses the `web` entrypoint.
#   Example:
#     ENABLE_ACME=false → entrypoints=web (no TLS), no HTTP→HTTPS redirect router emitted.

set -euo pipefail

ROUTER_NAME="${ROUTER_NAME:-${1:-}}"
DOMAIN="${DOMAIN:-${2:-}}"
CONTAINER_PORT="${CONTAINER_PORT:-${3:-}}"
ENABLE_ACME_RAW="${ENABLE_ACME:-${4:-true}}"
RESOLVER_NAME="${RESOLVER_NAME:-letsencrypt}"
DOMAIN_ALIASES_RAW="${DOMAIN_ALIASES:-${ALIASES:-}}"
INCLUDE_WWW_ALIAS="${INCLUDE_WWW_ALIAS:-false}"

# Normalize ACME toggle to true|false
case "${ENABLE_ACME_RAW,,}" in
  1|y|yes|true) ENABLE_ACME=true ;;
  0|n|no|false) ENABLE_ACME=false ;;
  *) ENABLE_ACME=true ;;
esac

if [[ -z "$ROUTER_NAME" || -z "$DOMAIN" || -z "$CONTAINER_PORT" ]]; then
  echo "::error::Usage: ROUTER_NAME=<name> DOMAIN=<fqdn> CONTAINER_PORT=<port> [ENABLE_ACME=true|false]" >&2
  echo "::error::Or: $0 <router_name> <domain> <container_port> [enable_acme]" >&2
  exit 2
fi

# Entrypoints: when ACME is enabled, use websecure; otherwise only web
if [[ "$ENABLE_ACME" == "true" ]]; then
  ENTRYPOINTS_VALUE="websecure"
else
  ENTRYPOINTS_VALUE="web"
fi

# Build host list for rule
HOSTS=()
DOMAIN_HOSTS_RAW="${DOMAIN_HOSTS:-}"
if [[ -n "$DOMAIN_HOSTS_RAW" ]]; then
  IFS=' ' read -r -a HOSTS <<< "$(echo "$DOMAIN_HOSTS_RAW" | tr ',' ' ')"
else
  HOSTS+=("$DOMAIN")
  if [[ -n "$DOMAIN_ALIASES_RAW" ]]; then
    IFS=' ' read -r -a _aliases <<< "$(echo "$DOMAIN_ALIASES_RAW" | tr ',' ' ')"
    for a in "${_aliases[@]}"; do
      [[ -z "$a" ]] && continue
      HOSTS+=("$a")
    done
  fi
  case "${INCLUDE_WWW_ALIAS,,}" in
    1|y|yes|true)
      HOSTS+=("www.${DOMAIN}")
      ;;
  esac
fi

# De-duplicate while preserving order
UNIQ_HOSTS=()
seen=""
for h in "${HOSTS[@]}"; do
  [[ -z "$h" ]] && continue
  if [[ ",${seen}," != *",${h},"* ]]; then
    UNIQ_HOSTS+=("$h")
    seen+="${seen:+,}${h}"
  fi
done

# Compose Host("a") || Host("b") expression for Traefik v3 (quote-safe, no backticks)
HOST_RULE_EXPR=""
for idx in "${!UNIQ_HOSTS[@]}"; do
  d="${UNIQ_HOSTS[$idx]}"
  if [[ $idx -gt 0 ]]; then HOST_RULE_EXPR+=" || "; fi
  HOST_RULE_EXPR+="Host(\"${d}\")"
done

# Emit base labels (newline-separated). TLS labels are gated by ENABLE_ACME.
printf '%s\n' \
  "--label" "traefik.enable=true" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.rule=${HOST_RULE_EXPR}" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.service=${ROUTER_NAME}" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.entrypoints=${ENTRYPOINTS_VALUE}" \
  "--label" "traefik.http.services.${ROUTER_NAME}.loadbalancer.server.port=${CONTAINER_PORT}"

if [[ "$ENABLE_ACME" == "true" ]]; then
  # With ACME, enable TLS and set the resolver on the primary router.
  printf '%s\n' \
    "--label" "traefik.http.routers.${ROUTER_NAME}.tls=true" \
    "--label" "traefik.http.routers.${ROUTER_NAME}.tls.certresolver=${RESOLVER_NAME}"
fi

# HTTP redirect router (only when ACME/TLS is enabled)
if [[ "$ENABLE_ACME" == "true" ]]; then
  printf '%s\n' \
    "--label" "traefik.http.routers.${ROUTER_NAME}-http.rule=${HOST_RULE_EXPR}" \
    "--label" "traefik.http.routers.${ROUTER_NAME}-http.entrypoints=web" \
    "--label" "traefik.http.routers.${ROUTER_NAME}-http.service=${ROUTER_NAME}" \
    "--label" "traefik.http.middlewares.${ROUTER_NAME}-https-redirect.redirectscheme.scheme=https" \
    "--label" "traefik.http.routers.${ROUTER_NAME}-http.middlewares=${ROUTER_NAME}-https-redirect"
fi
