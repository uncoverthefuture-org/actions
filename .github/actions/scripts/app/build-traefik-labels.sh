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

# Entrypoints: favor websecure first when ACME is enabled
if [[ "$ENABLE_ACME" == "true" ]]; then
  ENTRYPOINTS_VALUE="websecure,web"
else
  ENTRYPOINTS_VALUE="web,websecure"
fi

# Build host list for rule
HOSTS=()
HOSTS+=("$DOMAIN")

# Parse aliases (comma or whitespace separated)
if [[ -n "$DOMAIN_ALIASES_RAW" ]]; then
  # Replace commas with spaces, then iterate
  IFS=' ' read -r -a _aliases <<< "$(echo "$DOMAIN_ALIASES_RAW" | tr ',' ' ')"
  for a in "${_aliases[@]}"; do
    [[ -z "$a" ]] && continue
    HOSTS+=("$a")
  done
fi

# Optional www alias
case "${INCLUDE_WWW_ALIAS,,}" in
  1|y|yes|true)
    HOSTS+=("www.${DOMAIN}")
    ;;
esac

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

# Compose Host(`a`,`b`) argument
HOST_RULE_ARGS=""
for idx in "${!UNIQ_HOSTS[@]}"; do
  d="${UNIQ_HOSTS[$idx]}"
  if [[ $idx -gt 0 ]]; then HOST_RULE_ARGS+=","; fi
  HOST_RULE_ARGS+="\`${d}\`"
done

# Emit labels (newline-separated) with proper quoting
printf '%s\n' \
  "--label" "traefik.enable=true" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.rule=Host(${HOST_RULE_ARGS})" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.service=${ROUTER_NAME}" \
  "--label" "traefik.http.routers.${ROUTER_NAME}.entrypoints=${ENTRYPOINTS_VALUE}" \
  "--label" "traefik.http.services.${ROUTER_NAME}.loadbalancer.server.port=${CONTAINER_PORT}"

if [[ "$ENABLE_ACME" == "true" ]]; then
  printf '%s\n' "--label" "traefik.http.routers.${ROUTER_NAME}.tls.certresolver=${RESOLVER_NAME}"
fi
