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
  if command -v traefik_fix_cni_config_version >/dev/null 2>&1; then
    traefik_fix_cni_config_version "$network_name" "$debug" || true
  fi
  printf '%s' "--network $network_name"
}

traefik_fix_cni_config_version() {
  local network_name="$1"
  local debug="${2:-}"
  if [[ -z "$network_name" ]]; then return 0; fi

  local conf_dir conf_file
  if [ "$(id -u)" -eq 0 ]; then
    conf_dir="/etc/cni/net.d"
  else
    conf_dir="$HOME/.config/cni/net.d"
  fi
  conf_file="$conf_dir/${network_name}.conflist"

  if [ ! -f "$conf_file" ]; then
    traefik_util_debug "$debug" "No CNI config found for '$network_name' at $conf_file; skipping version fix"
    return 0
  fi

  if grep -q '"cniVersion"[[:space:]]*:[[:space:]]*"1.0.0"' "$conf_file" 2>/dev/null; then
    traefik_util_debug "$debug" "Downgrading CNI cniVersion to 0.4.0 for '$network_name' ($conf_file)"
    if command -v sed >/dev/null 2>&1; then
      if ! sed -i 's/"cniVersion"[[:space:]]*:[[:space:]]*"1.0.0"/"cniVersion": "0.4.0"/' "$conf_file" 2>/dev/null; then
        echo "::warning::Failed to rewrite CNI cniVersion in $conf_file" >&2
      fi
    else
      echo "::warning::sed not available; cannot adjust CNI cniVersion in $conf_file" >&2
    fi
  fi
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
  local acme_email
  local dashboard_host external_dashboard_router=""

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

  # Decide which email string to embed in the static config. When an explicit
  # email is provided, write it directly so Let's Encrypt sees a concrete
  # contact address. When empty, fall back to a placeholder that can be set
  # via TRAEFIK_EMAIL (used only in legacy/diagnostic scenarios).
  if [[ -n "$email" ]]; then
    acme_email="$email"
  else
    acme_email='${TRAEFIK_EMAIL}'
  fi

  # Optional external dashboard host (for example traefik.example.com) can be
  # provided via DASHBOARD_HOST. When set, we expose the internal API
  # (api@internal) on the websecure entrypoint with TLS via the letsencrypt
  # resolver, protected by the same basic auth middleware that guards the
  # internal-dashboard router on the dedicated dashboard entrypoint.
  dashboard_host="${DASHBOARD_HOST:-}"
  if [[ -n "$dashboard_host" ]]; then
    # Indented block to splice directly into the http.routers section below.
    read -r -d '' external_dashboard_router <<EOR || true
    external-dashboard:
      entryPoints:
        - websecure
      rule: "Host(\`$dashboard_host\`) && PathPrefix(\`/\`)"
      middlewares:
        - internal-dashboard-auth
      service: "api@internal"
      tls:
        certResolver: letsencrypt
EOR
  fi

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
      email: "$acme_email"
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
${external_dashboard_router:+$external_dashboard_router}
  services:
    noop:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1"
EOF
}

# cleanup_existing_traefik
#   Stops and removes the "traefik" container and its associated user-level
#   systemd unit when present. Safe to call even when Traefik is not running.
#   Example:
#     # Ensure we can re-create the Traefik container without name conflicts
#     cleanup_existing_traefik
cleanup_existing_traefik() {
  echo "🧹 Cleaning up existing Traefik container ..."
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active --quiet container-traefik.service 2>/dev/null; then
      systemctl --user stop container-traefik.service >/dev/null 2>&1 || true
    fi
  fi

  if podman container exists traefik >/dev/null 2>&1; then
    status=$(podman inspect -f '{{.State.Status}}' traefik 2>/dev/null || true)
    if [[ "$status" = "running" || "$status" = "stopping" || "$status" = "paused" ]]; then
      podman stop -t 15 traefik >/dev/null 2>&1 || true
    fi

    for i in {1..10}; do
      status=$(podman inspect -f '{{.State.Status}}' traefik 2>/dev/null || true)
      if [[ -z "$status" || "$status" = "exited" || "$status" = "dead" ]]; then
        break
      fi
      sleep 1
    done

    status=$(podman inspect -f '{{.State.Status}}' traefik 2>/dev/null || true)
    if [[ -n "$status" && "$status" != "" && "$status" != "exited" ]]; then
      podman kill traefik >/dev/null 2>&1 || true
    fi
    podman rm -f traefik >/dev/null 2>&1 || true

    for i in {1..10}; do
      if ! podman container exists traefik >/dev/null 2>&1; then
        echo "  ✓ Traefik container name is free"
        break
      fi
      sleep 1
    done
  fi
}

# ensure_traefik_systemd_user_service
#   Generates (or refreshes) the user-level systemd unit for the "traefik"
#   container using `podman generate systemd`, installs it under
#   ~/.config/systemd/user, and enables it via `systemctl --user` when
#   possible. This allows Traefik to restart automatically for the podman
#   user after reboots.
#
#   Podman now recommends Quadlet-based units for new setups. This helper is
#   intentionally kept as a legacy persistence path for container-mode
#   deployments so existing workflows continue to function, while the
#   Quadlet-based flow (for example, install-quadlet-sockets.sh +
#   traefik.container) can be adopted gradually.
#   Example:
#     # After confirming Traefik is healthy, persist it via systemd user unit
#     ensure_traefik_systemd_user_service
ensure_traefik_systemd_user_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "::notice::systemctl not available; skipping user-level persistence." >&2
    return 0
  fi

  echo "🧾 Generating/refreshing systemd user service for Traefik ..."
  if ! podman container exists traefik >/dev/null 2>&1; then
    echo "::warning::Traefik container not found; cannot generate systemd unit." >&2
    return 0
  fi

  if podman generate systemd --files --name traefik >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/systemd/user"
    local unit_tmp="container-traefik.service"
    local unit_path="$HOME/.config/systemd/user/container-traefik.service"
    if mv -f "$unit_tmp" "$unit_path" 2>/dev/null; then
      if command -v sed >/dev/null 2>&1; then
        sed -i '/^PIDFile=/d' "$unit_path" 2>/dev/null || true
        if grep -q '^Type=' "$unit_path"; then
          sed -i 's/^Type=.*/Type=oneshot/' "$unit_path" 2>/dev/null || true
        else
          sed -i 's/^\[Service\]/[Service]\nType=oneshot/' "$unit_path" 2>/dev/null || true
        fi
        if ! grep -q '^RemainAfterExit=' "$unit_path"; then
          sed -i 's/^Type=oneshot$/Type=oneshot\nRemainAfterExit=yes/' "$unit_path" 2>/dev/null || true
        fi
      fi

      if systemctl --user daemon-reload >/dev/null 2>&1; then
        if systemctl --user enable --now container-traefik.service >/dev/null 2>&1; then
          echo "  ✓ Installed/updated container-traefik.service and enabled persistence"
        else
          echo "::warning::Failed to enable/start container-traefik.service (user systemd may be unavailable)." >&2
        fi
      else
        echo "::warning::systemctl --user daemon-reload failed; user-level systemd may be unavailable." >&2
      fi
    else
      echo "::warning::Failed to install container-traefik.service; check permissions." >&2
    fi
  else
    echo "::warning::podman generate systemd not available; skipping persistence." >&2
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
