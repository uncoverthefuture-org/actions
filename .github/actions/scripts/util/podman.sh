#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# podman.sh - Podman helpers for container port resolution and run orchestration
# -----------------------------------------------------------------------------

# Requires: validate_port_number, port_in_use, find_available_port

# Resolve container port from input, Traefik label, or env fallback
podman_resolve_container_port() {
  local in_port="$1" traefik_enabled="$2" router_name="$3" container_name="$4" debug="${5:-false}"
  local port="$in_port"

  if [[ -z "$port" && "$traefik_enabled" == "true" && -n "$router_name" && -n "$container_name" ]]; then
    local runner="run_podman"; command -v run_podman >/dev/null || runner="podman"
    port=$($runner inspect -f "{{ index .Config.Labels \"traefik.http.services.${router_name}.loadbalancer.server.port\" }}" "$container_name" 2>/dev/null || true)
  fi

  port="${port:-${WEB_CONTAINER_PORT:-${TARGET_PORT:-${PORT:-8080}}}}"

  if ! validate_port_number "$port"; then
    echo "::error::Invalid container port '$port'" >&2
    return 1
  fi

  [[ "$debug" == "true" ]] && echo "🌐 Resolved container port: $port" >&2
  printf '%s' "$port"
}

# Resolve host port from input, container mapping, file, or fallback
podman_resolve_host_port() {
  local in_port="$1" container_name="$2" container_port="$3" host_port_file="$4" debug="${5:-false}"
  local host_port="$in_port" source="input" auto_assigned=false existing_port=""

  if [[ -z "$host_port" && -n "$container_name" && -n "$container_port" ]]; then
    local runner="run_podman"; command -v run_podman >/dev/null || runner="podman"
    local port_line=$($runner port "$container_name" "${container_port}/tcp" 2>/dev/null || true)
    if [[ "$port_line" =~ :([0-9]+)$ ]]; then
      host_port="${BASH_REMATCH[1]}"
      source="existing"
      existing_port="$host_port"
    fi
  fi

  if [[ -z "$host_port" && -f "$host_port_file" ]]; then
    local stored
    stored=$(<"$host_port_file")
    if validate_port_number "$stored"; then
      host_port="$stored"; source="file"
    else
      echo "::warning::Invalid stored port '$stored' in $host_port_file" >&2
    fi
  fi

  host_port="${host_port:-${WEB_HOST_PORT:-${PORT:-8080}}}"
  [[ -z "$source" ]] && source="default"

  if ! validate_port_number "$host_port"; then
    echo "::warning::Invalid host port '$host_port'; defaulting to 8080" >&2
    host_port=8080; source="default"
  fi

  if port_in_use "$host_port" && [[ "$host_port" != "$existing_port" ]]; then
    echo "⚠️  Port $host_port in use; finding next available..." >&2
    host_port=$(find_available_port "$host_port" 500) || return 1
    auto_assigned=true; source="auto"
    echo "🔁 Auto-selected host port $host_port" >&2
  fi

  [[ "$source" != "input" ]] && echo "$host_port" > "$host_port_file" 2>/dev/null || true
  printf '%s %s %s' "$host_port" "$source" "$auto_assigned"
}

# Build DNS args for podman run
podman_build_dns_args() {
  local debug="${1:-false}"
  local src="/run/systemd/resolve/resolv.conf"
  if [[ -s "$src" ]]; then
    [[ "$debug" == "true" ]] && echo "🧭 DNS: mounting $src" >&2
    echo "-v=$src:/etc/resolv.conf:ro"
  else
    [[ "$debug" == "true" ]] && echo "🧭 DNS: using public resolvers" >&2
    echo "--dns=1.1.1.1" "--dns=8.8.8.8"
  fi
}

# Run podman container with preview
podman_run_with_preview() {
  local name="$1" env_file="$2" restart_policy="$3" memory_limit="$4" image_ref="$5"
  local extra_run_args="${6:-}" debug="${7:-}" 
  local port_ref_name="${8:-}" dns_ref_name="${9:-}" net_ref_name="${10:-}" 
  local label_ref_name="${11:-}" volume_ref_name="${12:-}"

  local -a port_args dns_args network_args label_args volume_args extra_args
  local -a cmd

  # Helper: safely expand array ref if name provided
  _expand_ref() {
    local ref_name="$1"
    if [[ -n "$ref_name" && -v "$ref_name" ]]; then
      local -n src="$ref_name"
      printf '%s\n' "${src[@]}"
    fi
  }

  # Expand all optional arrays
  readarray -t port_args    < <(_expand_ref "$port_ref_name")
  readarray -t dns_args     < <(_expand_ref "$dns_ref_name")
  readarray -t network_args < <(_expand_ref "$net_ref_name")
  readarray -t label_args   < <(_expand_ref "$label_ref_name")
  readarray -t volume_args  < <(_expand_ref "$volume_ref_name")

  # Parse extra args safely
  if [[ -n "$extra_run_args" ]]; then
    readarray -t extra_args < <(printf '%s\n' "$extra_run_args" | xargs -n1 printf '%s\n')
  fi

  # Build command
  cmd=(podman run -d --name "$name")

  [[ -s "$env_file" ]] && cmd+=(--env-file "$env_file")
  cmd+=("${port_args[@]}" --restart="$restart_policy")
  cmd+=("--memory=$memory_limit" "--memory-swap=$memory_limit")
  cmd+=("${dns_args[@]}" "${network_args[@]}" "${volume_args[@]}" "${extra_args[@]}" "${label_args[@]}")
  cmd+=("$image_ref")

  # Preview
  echo "podman run command (preview):"
  printf '  %q' "${cmd[@]}"; echo

  # Execute
  "${cmd[@]}"
}
# Login to registry if credentials are provided
podman_login_if_credentials() {
  local registry="$1" username="$2" token="$3"
  if [[ -n "$username" && -n "$token" ]]; then
    echo "🔐 Logging into $registry..."
    if printf '%s' "$token" | podman login "$registry" -u "$username" --password-stdin; then
      PODMAN_LOGIN_STATUS="logged_in"
    else
      PODMAN_LOGIN_STATUS="login_failed"; return 1
    fi
  else
    echo "ℹ️  No credentials provided; skipping login"
    PODMAN_LOGIN_STATUS="skipped"
  fi
  export PODMAN_LOGIN_STATUS
}

# Pull image and report status
podman_pull_image() {
  local image_ref="$1"
  echo "📥 Pulling image: $image_ref"
  if podman pull "$image_ref"; then
    PODMAN_PULL_STATUS="pulled"
  else
    PODMAN_PULL_STATUS="pull_failed"; return 1
  fi
  export PODMAN_PULL_STATUS
}

# Wrapper for podman (can be overridden)
run_podman() {
  podman "$@"
}

# Detect Traefik availability using systemd and podman checks
podman_detect_traefik() {
  local present=false
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet traefik; then
    present=true
  elif command -v podman >/dev/null 2>&1 && podman ps -a --format '{{.Names}}' | grep -Fxq traefik; then
    present=true
  elif command -v podman >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1 && sudo -n podman ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq traefik; then
    present=true
  fi

  if [[ "$present" == "true" ]]; then
    echo "✅ Traefik endpoint detected"
  else
    echo "⚠️  Traefik service not detected; deployment will rely on host port mapping unless ensured elsewhere"
  fi

  [[ "$present" == "true" ]]
}
