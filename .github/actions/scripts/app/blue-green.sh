#!/usr/bin/env bash
# Sourced by release-manager.sh. Owns file-provider routing for managed releases.

bluegreen_prepare() {
  local root="$1" id="$2" base="$3"; shift 3
  local -a original=("$@")
  local i arg label rule='' network="${TRAEFIK_NETWORK_NAME:-traefik-network}" network_seen=false
  local router="${ROUTER_NAME:-}" domain="${DOMAIN:-${DOMAIN_INPUT:-${DOMAIN_DEFAULT:-}}}" port="${CONTAINER_PORT:-}"
  local dynamic="${TRAEFIK_DYNAMIC_DIR:-$HOME/.config/traefik/dynamic}" inspect
  [[ "$router" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ && "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && "$port" =~ ^[0-9]+$ ]] || {
    release_error 'Blue-green requires a router name, domain and numeric container port'; return 1;
  }
  (( port > 0 && port < 65536 )) || return 1
  [[ "${TRAEFIK_ENABLED:-false}" == true ]] || { release_error 'Blue-green requires Traefik'; return 1; }
  [[ "${READINESS_PATH:-/}" =~ ^/[a-zA-Z0-9/._~-]*$ ]] || return 1
  inspect=$(podman inspect traefik) || { release_error 'A user-scoped Traefik container is required'; return 1; }
  printf '%s' "$inspect" | jq -e --arg source "$dynamic" --arg network "$network" '
    .[0] | .State.Running == true and
    (.NetworkSettings.Networks | has($network)) and
    any(.Mounts[]?; .Source == $source and .Destination == "/etc/traefik/dynamic")
  ' >/dev/null || {
    release_error 'Reconcile Traefik with the updated setup scripts during maintenance: a shared network and the dynamic-directory mount are required'
    return 1
  }
  [[ -d "$dynamic" && -w "$dynamic" ]] || { release_error 'Traefik dynamic directory is not writable'; return 1; }
  BG_ARGV=()
  for ((i=0; i<${#original[@]}; i++)); do
    arg="${original[$i]}"
    case "$arg" in
      -p|--publish|--publish=*|-p?*|-P|--publish-all|--pod|--pod=*|--ip|--ip=*)
        release_error 'Blue-green does not support published ports, pods or fixed container IPs'; return 1;;
      --name)
        BG_ARGV+=(--name "${base:0:55}-$id"); i=$((i+1));;
      --network)
        [[ "${original[$((i+1))]}" == "$network" ]] || { release_error 'Candidate must use the Traefik network'; return 1; }
        network_seen=true; BG_ARGV+=("$arg" "${original[$((i+1))]}"); i=$((i+1));;
      --network=*)
        [[ "${arg#*=}" == "$network" ]] || return 1
        network_seen=true; BG_ARGV+=("$arg");;
      --label|-l)
        label="${original[$((i+1))]}"; i=$((i+1))
        if [[ "$label" == "traefik.http.routers.$router.rule="* ]]; then rule="${label#*=}"; fi
        case "$label" in traefik.*) ;; *) BG_ARGV+=("$arg" "$label");; esac;;
      --label=*)
        label="${arg#*=}"
        if [[ "$label" == "traefik.http.routers.$router.rule="* ]]; then rule="${label#*=}"; fi
        case "$label" in traefik.*) ;; *) BG_ARGV+=("$arg");; esac;;
      *) BG_ARGV+=("$arg");;
    esac
  done
  [[ "$network_seen" == true && -n "$rule" ]] || { release_error 'Blue-green requires the shared Traefik network and a generated host rule'; return 1; }
  # Override image-embedded Traefik labels too: candidate discovery must remain
  # disabled even if the image itself sets traefik.enable=true.
  BG_ARGV=("${BG_ARGV[@]:0:${#BG_ARGV[@]}-1}" --label traefik.enable=false "${BG_ARGV[${#BG_ARGV[@]}-1]}")
  BG_NAME="${base:0:55}-$id"
  BG_ROUTING=$(jq -n --arg key "$router" --arg dir "$dynamic" --arg domain "$domain" --arg path "${READINESS_PATH:-/}" \
    --argjson tls "${TRAEFIK_ENABLE_ACME:-true}" '{key:$key,directory:$dir,domain:$domain,path:$path,tls:$tls}') || return
  BG_ROUTE=$(jq -n --arg key "$router" --arg rule "$rule" --arg name "$BG_NAME" --arg port "$port" --arg id "$id" \
    --argjson tls "${TRAEFIK_ENABLE_ACME:-true}" '
    {http:{routers:{($key):{rule:$rule,service:$key,entryPoints:[if $tls then "websecure" else "web" end],middlewares:[($key+"-release")]}},
      services:{($key):{loadBalancer:{servers:[{url:("http://"+$name+":"+$port)}]}}},
      middlewares:{($key+"-release"):{headers:{customResponseHeaders:{"X-UActions-Release":$id}}}}}}
    | if $tls then
      .http.routers[$key].tls={certResolver:"letsencrypt"}
      | .http.routers[$key+"-http"]={rule:$rule,service:$key,entryPoints:["web"],middlewares:[($key+"-redirect")]}
      | .http.middlewares[$key+"-redirect"]={redirectScheme:{scheme:"https"}}
      else . end') || return
  if [[ ! -f "$root/state.json" ]]; then
    if podman container exists "$base" >/dev/null 2>&1 || [[ -e "$dynamic/uactions-$router.json" ]]; then
      release_error 'An unmanaged container or route already exists; migrate it explicitly before blue-green deployment'; return 1
    fi
  fi
}

bluegreen_publish() {
  local dir="$1" destination key temporary
  destination=$(jq -er '.routing.directory' "$dir/release.json") || return
  key=$(jq -er '.routing.key' "$dir/release.json") || return
  temporary=$(mktemp "$destination/.uactions-$key-XXXXXXXX") || return
  if ! cp "$dir/route.json" "$temporary" || ! chmod 600 "$temporary" || ! mv "$temporary" "$destination/uactions-$key.json"; then
    rm -f "$temporary"; return 1
  fi
}

bluegreen_verify() {
  local dir="$1" domain path id scheme port attempt headers
  domain=$(jq -er '.routing.domain' "$dir/release.json") || return
  path=$(jq -r '.routing.path' "$dir/release.json") || return
  id=$(jq -er '.id' "$dir/release.json") || return
  scheme=http; port=80
  if [[ "$(jq -r '.routing.tls' "$dir/release.json")" == true ]]; then scheme=https; port=443; fi
  headers=$(mktemp) || return
  for ((attempt=0; attempt<30; attempt++)); do
    # Resolve directly to this host, preserve Host/SNI, validate TLS, and require
    # the release marker. A cached DNS response or the previous router cannot pass.
    if curl --noproxy '*' --silent --show-error --fail --max-time 5 \
      --resolve "$domain:$port:127.0.0.1" --dump-header "$headers" --output /dev/null \
      "$scheme://$domain$path" 2>/dev/null &&
      tr -d '\r' < "$headers" | grep -Eiq "^X-UActions-Release: $id$"; then
      rm -f "$headers"; return 0
    fi
    sleep 2
  done
  rm -f "$headers"
  release_error 'Traefik did not serve the expected healthy release'
}

bluegreen_transition() {
  local root="$1" target="$2" current='' old='' obsolete='' target_dir name routing last_switch=0 remaining=0
  target_dir="$root/releases/$target"
  release_check "$target_dir" || return
  if [[ -f "$root/state.json" ]]; then
    current=$(jq -er '.current' "$root/state.json") || return
    release_valid_id "$current" || return 1
    [[ "$current" != "$target" ]] || return 0
    old="$root/releases/$current"
    release_check "$old" || return
    [[ "$(jq -r '.strategy // "recreate"' "$old/release.json")" == blue-green ]] || {
      release_error 'Switching between recreate and blue-green requires an explicit migration'; return 1;
    }
    # Routing ownership must stay stable; all version-specific route settings
    # (hosts, TLS and readiness path) come from the selected snapshot.
    [[ "$(jq -c '.routing | {key,directory}' "$old/release.json")" == "$(jq -c '.routing | {key,directory}' "$target_dir/release.json")" ]] || {
      release_error 'Blue-green rollback/promotion requires unchanged router identity and dynamic directory'; return 1;
    }
    obsolete=$(jq -r '.previous // empty' "$root/state.json") || return
    last_switch=$(jq -r '.activated_at // 0 | floor' "$root/state.json") || return
  fi
  name=$(jq -er '.container' "$target_dir/release.json") || return
  if ! release_start "$target_dir" || ! release_persist "$target_dir"; then
    release_service_stop "$target_dir" || true
    podman rm --force "$name" >/dev/null 2>&1 || true
    return 1
  fi
  if bluegreen_publish "$target_dir" && bluegreen_verify "$target_dir" && release_commit "$root" "$target" "$current"; then
    # Keep the previous active release running. Retire only the older standby;
    # it has already been off traffic since the preceding successful promotion.
    if [[ -n "$obsolete" && "$obsolete" != "$target" && "$obsolete" != "$current" ]]; then
      remaining=$((30 - ($(date +%s) - last_switch)))
      if (( remaining > 0 && remaining <= 30 )); then sleep "$remaining"; fi
      if release_valid_id "$obsolete" && release_check "$root/releases/$obsolete"; then
        release_service_stop "$root/releases/$obsolete" || echo '::warning::Could not disable obsolete standby service' >&2
        podman stop --time 30 "$(jq -r '.container' "$root/releases/$obsolete/release.json")" >/dev/null || echo '::warning::Could not stop obsolete standby container' >&2
      fi
    fi
    printf 'Active blue-green release: %s\n' "$target"
    return 0
  fi
  if [[ -n "$old" ]]; then
    if ! bluegreen_publish "$old" || ! bluegreen_verify "$old"; then
      release_error 'Traffic recovery could not be verified; both releases are retained for investigation'
      return 1
    fi
  else
    routing=$(jq -r '.routing.directory + "/uactions-" + .routing.key + ".json"' "$target_dir/release.json") || return
    rm -f "$routing" || return
  fi
  release_service_stop "$target_dir" || true
  podman rm --force "$name" >/dev/null 2>&1 || true
  release_error 'Blue-green promotion failed; active state was not changed'
}
