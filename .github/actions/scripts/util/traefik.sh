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

# traefik_util_debug_enabled [flag]
#   Returns 0 when debugging should be emitted. Takes an explicit flag argument
#   when provided, else falls back to TRAEFIK_UTIL_DEBUG, then DEBUG.
traefik_util_debug_enabled() {
  local flag="${1:-}"
  local fallback="${TRAEFIK_UTIL_DEBUG:-${DEBUG:-false}}"
  local value="${flag:-$fallback}"
  case "${value,,}" in
    1|y|yes|true) return 0 ;;
  esac
  return 1
}

# traefik_util_debug <flag?> <message>
#   Emits a debug line when the provided flag (or environment fallback) enables
#   debug output. Usage: traefik_util_debug "$debug" "message".
traefik_util_debug() {
  local flag="${1:-}"; shift || true
  local message="$*"
  if traefik_util_debug_enabled "$flag" && [[ -n "$message" ]]; then
    printf '🔍 [traefik util] %s\n' "$message" >&2
  fi
}

# ensure_traefik_network <network_name> [debug]
#   Creates the given podman network if it doesn't exist and echoes
#   a "--network <network_name>" token on stdout (or nothing when name is empty).
#   Example:
#     arg=$(ensure_traefik_network "traefik-network" "${DEBUG:-false}")
#     [[ -n "$arg" ]] && NETWORK_ARGS+=("$arg")
ensure_traefik_network() {
  local network_name="$1"
  local debug="${2:-}"
  traefik_util_debug "$debug" "Ensuring Traefik network '$network_name' exists"
  if [[ -z "$network_name" ]]; then return 0; fi
  if ! command -v podman >/dev/null 2>&1; then return 0; fi
  if ! podman network exists "$network_name" >/dev/null 2>&1; then
    traefik_util_debug "$debug" "Creating Traefik network '$network_name'"
    podman network create "$network_name" >/dev/null
  fi
  printf '%s' "--network $network_name"
}

# generate_traefik_static_config <dest_path> [email] [log_level] [debug]
#   Writes the canonical Traefik static configuration (matching install-traefik)
#   to <dest_path>. When an email is provided, replaces the ACME placeholder with
#   that value. Log level defaults to DEBUG when omitted.
#   Example:
#     generate_traefik_static_config "$TMP" "ops@example.com" "DEBUG" "${DEBUG:-false}"
generate_traefik_static_config() {
  local dest="$1"
  local email="${2:-}"
  local log_level_raw="${3:-INFO}"
  local debug="${4:-}"
  local log_level="${log_level_raw^^}"

  # Validate log level
  case "$log_level" in
    ERROR|WARN|INFO|DEBUG) ;;
    *) log_level="INFO" ;;
  esac

  if [[ -z "$dest" ]]; then
    echo "::error::generate_traefik_static_config requires a destination path" >&2
    return 1
  fi

  traefik_util_debug "$debug" "Generating Traefik static config at '$dest' (log level: $log_level)"

  cat >"$dest" <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  dashboard:
    address: ":8080"
  metrics:
    address: ":8082"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

api:
  dashboard: true
  insecure: false

ping:
  entryPoint: web

log:
  level: "$log_level"
  format: common
  filePath: "/var/log/traefik/traefik.log"

accessLog:
  format: common
  filePath: "/var/log/traefik/access.log"

metrics:
  prometheus:
    entryPoint: "metrics"
    addRoutersLabels: true
    addServicesLabels: true

# ACME resolver: explicitly target the official Let's Encrypt production
# directory so that production deployments never accidentally use the
# staging CA (which browsers do not trust). Example:
#   - caServer: https://acme-v02.api.letsencrypt.org/directory
certificatesResolvers:
  letsencrypt:
    acme:
      caServer: https://acme-v02.api.letsencrypt.org/directory
      email: "\${TRAEFIK_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

http:
  middlewares:
    internal-dashboard-auth:
      basicAuth:
        usersFile: "/etc/traefik/dashboard-users"
  routers:
    internal-dashboard:
      entryPoints:
        - dashboard
      rule: "PathPrefix(\`/\`)"
      middlewares:
        - internal-dashboard-auth
      service: "api@internal"
      tls:
        certResolver: letsencrypt
  services:
    noop:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1"
EOF

  if [[ -n "$email" ]]; then
    python3 -c "
import sys, re
path, email = sys.argv[1:3]
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r'email:\s*\"?\${TRAEFIK_EMAIL[^\"]*\"?', f'email: \"{email}\"', content)
with open(path, 'w') as f:
    f.write(content)
" "$dest" "$email"
    traefik_util_debug "$debug" "Set ACME email to '$email'"
  fi
}

# build_traefik_labels_fallback \
#   <router_name> <domain> <container_port> <enable_acme> \
#   <domain_hosts> <domain_aliases> <include_www_alias> <network_name>
#   [debug]
#   Emits one --label per line that can be consumed via `mapfile -t`.
#   Example:
#     mapfile -t LABELS < <(build_traefik_labels_fallback "$ROUTER" "$DOMAIN" 8080 true "" "alt.example.com" false "traefik-network" "${DEBUG:-false}")
build_traefik_labels_fallback() {
  local router_name="$1"; shift
  local domain="$1"; shift
  local container_port="$1"; shift
  local enable_acme="$1"; shift
  local domain_hosts="$1"; shift
  local domain_aliases="$1"; shift
  local include_www_alias="$1"; shift
  local network_name="$1"; shift || true
  local debug="${1:-}"

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

    # When DOMAIN is already a www.<apex> host (for example when compute-defaults
    # is given base_domain=admissionboox.com and uses the default production
    # prefix "www" → DOMAIN=www.admissionboox.com), auto-add the apex variant so
    # both example.com and www.example.com are covered by the same router and
    # certificate. Example:
    #   domain=www.admissionboox.com → hosts=[www.admissionboox.com, admissionboox.com]
    dom_lower="$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"
    if [[ "$dom_lower" == www.* ]]; then
      apex_candidate="${dom_lower#www.}"
      if [[ -n "$apex_candidate" ]]; then
        hosts+=("$apex_candidate")
      fi
    fi
  fi

  # De-duplicate
  for val in "${hosts[@]}"; do
    [[ -z "$val" ]] && continue
    if [[ ",${seen}," != *",${val},"* ]]; then
      uniq_hosts+=("$val"); seen+="${seen:+,}${val}"
    fi
  done

  if traefik_util_debug_enabled "$debug"; then
    traefik_util_debug "$debug" "Router '$router_name' hosts: ${uniq_hosts[*]}"
  fi

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
