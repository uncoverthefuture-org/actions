#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# traefik.sh - Helpers to build Traefik labels and ensure network
# -----------------------------------------------------------------------------
# Purpose:
#   Provide reusable helpers for composing Traefik v3 labels when the dedicated
#   label-builder script is unavailable, and to ensure the Traefik network
#   exists before attaching app containers.
# -----------------------------------------------------------------------------

# ensure_traefik_network <network_name> [debug]
#   Creates the given podman network if it doesn't exist and echoes
#   a "--network <network_name>" token on stdout (or nothing when name is empty).
#   Example:
#     arg=$(ensure_traefik_network "traefik-network" "${DEBUG:-false}")
#     [[ -n "$arg" ]] && NETWORK_ARGS+=("$arg")
ensure_traefik_network() {
  local network_name="$1"
  local debug="${2:-false}"
  if [[ -z "$network_name" ]]; then return 0; fi
  if ! command -v podman >/dev/null 2>&1; then return 0; fi
  if ! podman network exists "$network_name" >/dev/null 2>&1; then
    [[ "$debug" == "true" ]] && echo "🌐 Creating Traefik network $network_name" >&2
    podman network create "$network_name" >/dev/null
  fi
  printf '%s' "--network $network_name"
}

# build_traefik_labels_fallback \
#   <router_name> <domain> <container_port> <enable_acme> \
#   <domain_hosts> <domain_aliases> <include_www_alias> <network_name>
#   Emits one --label per line that can be consumed via `mapfile -t`.
#   Example:
#     mapfile -t LABELS < <(build_traefik_labels_fallback "$ROUTER" "$DOMAIN" 8080 true "" "alt.example.com" false "traefik-network")
build_traefik_labels_fallback() {
  local router_name="$1"; shift
  local domain="$1"; shift
  local container_port="$1"; shift
  local enable_acme="$1"; shift
  local domain_hosts="$1"; shift
  local domain_aliases="$1"; shift
  local include_www_alias="$1"; shift
  local network_name="$1"; shift || true

  # Build host list with precedence: explicit hosts, else domain + aliases (+www apex)
  local -a hosts uniq_hosts _aliases parts
  local seen="" dom_lower apex count val
  if [[ -n "$domain_hosts" ]]; then
    read -r -a hosts <<<"$(echo "$domain_hosts" | tr ',' ' ')"
  else
    hosts+=("$domain")
    if [[ -n "$domain_aliases" ]]; then
      read -r -a _aliases <<<"$(echo "$domain_aliases" | tr ',' ' ')"
      for val in "${_aliases[@]}"; do
        [[ -z "$val" ]] && continue
        hosts+=("$val")
      done
    fi
    case "${include_www_alias,,}" in
      1|y|yes|true)
        dom_lower="$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"
        IFS='.' read -r -a parts <<<"$dom_lower"; count=${#parts[@]}
        if (( count >= 2 )); then
          apex="${parts[count-2]}.${parts[count-1]}"
          if [[ "$dom_lower" = "$apex" ]]; then
            hosts+=("www.${apex}")
          fi
        fi
        ;;
    esac
  fi

  # De-duplicate
  for val in "${hosts[@]}"; do
    [[ -z "$val" ]] && continue
    if [[ ",${seen}," != *",${val},"* ]]; then
      uniq_hosts+=("$val"); seen+="${seen:+,}${val}"
    fi
  done

  # Compose Host("a") || Host("b")
  local host_rule_expr=""
  local i
  for i in "${!uniq_hosts[@]}"; do
    val="${uniq_hosts[$i]}"
    if [[ $i -gt 0 ]]; then host_rule_expr+=" || "; fi
    host_rule_expr+="Host(\"${val}\")"
  done

  printf -v router_rule 'traefik.http.routers.%s.rule=%s' "$router_name" "$host_rule_expr"
  printf -v router_service 'traefik.http.routers.%s.service=%s' "$router_name" "$router_name"
  printf -v service_port 'traefik.http.services.%s.loadbalancer.server.port=%s' "$router_name" "$container_port"

  echo "--label $router_rule"
  echo "--label $router_service"
  if [[ "${enable_acme,,}" == "true" ]]; then
    echo "--label traefik.http.routers.${router_name}.entrypoints=websecure"
    echo "--label traefik.http.routers.${router_name}.tls=true"
    echo "--label traefik.http.routers.${router_name}.tls.certresolver=letsencrypt"
  else
    echo "--label traefik.http.routers.${router_name}.entrypoints=web"
  fi
  echo "--label $service_port"
  if [[ -n "$network_name" ]]; then
    echo "--label traefik.docker.network=${network_name}"
  fi

  # Optional HTTP redirect when TLS enabled
  if [[ "${enable_acme,,}" == "true" ]]; then
    printf -v router_http_rule 'traefik.http.routers.%s-http.rule=%s' "$router_name" "$host_rule_expr"
    echo "--label $router_http_rule"
    echo "--label traefik.http.routers.${router_name}-http.entrypoints=web"
    echo "--label traefik.http.routers.${router_name}-http.service=${router_name}"
    echo "--label traefik.http.middlewares.${router_name}-https-redirect.redirectscheme.scheme=https"
    echo "--label traefik.http.routers.${router_name}-http.middlewares=${router_name}-https-redirect"
  fi
}
