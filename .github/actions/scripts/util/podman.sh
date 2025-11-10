#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# podman.sh - Podman-related helpers (port resolvers)
# -----------------------------------------------------------------------------
# Purpose:
#   Provide helpers that depend on Podman inspection to resolve container and
#   host ports consistently across scripts.
#
# Requirements:
#   - Callers should source util/ports.sh first so validate_port_number,
#     port_in_use, and find_available_port are available.
#   - Optionally define a wrapper function `run_podman()` (falls back to `podman`).
# -----------------------------------------------------------------------------

# podman_resolve_container_port <container_port_in> <traefik_enabled> <router_name> <container_name> [debug]
#   Determines the container's service port using the following precedence:
#   1) Explicit input (<container_port_in>)
#   2) Existing Traefik label on the container (when enabled)
#   3) Environment fallbacks: WEB_CONTAINER_PORT, TARGET_PORT, PORT (default 8080)
#   Emits the resolved port to stdout and exits non-zero if invalid.
#   Example:
#     CONTAINER_PORT="$(podman_resolve_container_port "$CONTAINER_PORT_IN" "$TRAEFIK_ENABLED" "$ROUTER_NAME" "$CONTAINER_NAME" "${DEBUG:-false}")"
podman_resolve_container_port() {
  local in_port="$1"; shift
  local traefik_enabled="$1"; shift
  local router_name="$1"; shift
  local container_name="$1"; shift
  local debug="${1:-false}"

  local port="$in_port"
  if [[ -z "$port" ]]; then
    if [[ "$traefik_enabled" == "true" && -n "$router_name" && -n "$container_name" ]] && command -v podman >/dev/null 2>&1; then
      # Requires caller to have defined run_podman alias; fall back to plain podman
      local _runner="run_podman"; command -v run_podman >/dev/null 2>&1 || _runner="podman"
      local old_label
      old_label=$($_runner inspect -f "{{ index .Config.Labels \"traefik.http.services.${router_name}.loadbalancer.server.port\" }}" "$container_name" 2>/dev/null || true)
      if [[ -n "$old_label" ]]; then
        port="$old_label"
      fi
    fi
    if [[ -z "$port" ]]; then
      port="${WEB_CONTAINER_PORT:-${TARGET_PORT:-${PORT:-8080}}}"
    fi
  fi

  if ! validate_port_number "$port"; then
    echo "::error::Invalid container port '$port'. Expected integer between 1-65535." >&2
    return 1
  fi
  [[ "$debug" == "true" ]] && echo "🌐 Resolved container port: $port" >&2
  printf '%s' "$port"
}

# podman_resolve_host_port <host_port_in> <container_name> <container_port> <host_port_file> [debug]
#   Resolves the host port with precedence:
#   1) Explicit input (<host_port_in>)
#   2) Existing mapping from container (podman port)
#   3) Stored file (<host_port_file>)
#   4) Defaults: WEB_HOST_PORT, PORT, finally 8080
#   Attempts to auto-find the next available port when occupied.
#   Persists non-input selections to <host_port_file>.
#   Outputs three space-separated fields: "<host_port> <source> <auto_assigned(true/false)>".
#   Example:
#     read HOST_PORT HOST_PORT_SOURCE AUTO_ASSIGNED <<<"$(podman_resolve_host_port "$HOST_PORT_IN" "$CONTAINER_NAME" "$CONTAINER_PORT" "$HOST_PORT_FILE" "${DEBUG:-false}")"
podman_resolve_host_port() {
  local in_port="$1"; shift
  local container_name="$1"; shift
  local container_port="$1"; shift
  local host_port_file="$1"; shift
  local debug="${1:-false}"

  local source="input"
  local host_port="$in_port"
  local old_port_line=""
  local auto_assigned=false

  if [[ -z "$host_port" ]]; then
    source=""
    if command -v podman >/dev/null 2>&1; then
      local _runner="run_podman"; command -v run_podman >/dev/null 2>&1 || _runner="podman"
      old_port_line=$($_runner port "$container_name" "${container_port}/tcp" 2>/dev/null || true)
      if [[ -n "$old_port_line" ]]; then
        host_port="$(echo "$old_port_line" | sed -E 's/.*:([0-9]+)$/\1/')"
        source="existing"
      fi
    fi
  fi

  if [[ -z "$host_port" && -f "$host_port_file" ]]; then
    local stored
    stored="$(tr -d ' \t\r\n' < "$host_port_file" 2>/dev/null || true)"
    if [[ -n "$stored" ]] && validate_port_number "$stored"; then
      host_port="$stored"; source="file"
    elif [[ -n "$stored" ]]; then
      echo "::warning::Ignoring stored host port '$stored' in $host_port_file (invalid)." >&2
    fi
  fi

  if [[ -z "$host_port" ]]; then
    host_port="${WEB_HOST_PORT:-${PORT:-8080}}"; source="default"
  fi

  if [[ -z "$host_port" ]]; then
    echo "::error::Failed to resolve host port" >&2
    return 1
  fi

  if ! validate_port_number "$host_port"; then
    echo "::warning::Host port '$host_port' is invalid; defaulting to 8080." >&2
    host_port=8080; source="default"
  fi

  # If occupied and not the same as the existing mapping, auto-advance
  local existing_port=""
  if [[ -n "$old_port_line" ]]; then
    local cnt
    cnt=$(printf '%s\n' "$old_port_line" | wc -l | tr -d ' ')
    if [[ "$cnt" == "1" ]]; then
      existing_port="$(printf '%s\n' "$old_port_line" | sed -E 's/.*:([0-9]+)$/\1/')"
    fi
  fi

  if port_in_use "$host_port"; then
    if [[ -n "$existing_port" && "$existing_port" == "$host_port" ]]; then
      [[ "$debug" == "true" ]] && echo "ℹ️  Reusing host port $host_port from existing container" >&2
    else
      echo "⚠️  Host port $host_port is already in use; searching for the next available port." >&2
      local new_port
      new_port="$(find_available_port "$host_port" 500)" || true
      if [[ -z "$new_port" ]]; then
        echo "::error::Unable to find an available port starting from $host_port" >&2
        return 1
      fi
      echo "🔁 Auto-selected host port $new_port" >&2
      host_port="$new_port"; source="auto"; auto_assigned=true
    fi
  fi

  # Persist when not explicitly provided
  if [[ "$source" != "input" ]]; then
    if ! printf '%s\n' "$host_port" > "$host_port_file"; then
      echo "::warning::Failed to persist host port to $host_port_file" >&2
    elif [[ "$debug" == "true" && "$auto_assigned" == "true" ]]; then
      echo "💾 Persisted host port assignment" >&2
    fi
  fi

  printf '%s %s %s' "$host_port" "$source" "$auto_assigned"
}

# podman_build_dns_args [debug]
#   Emits arguments suitable for `podman run` to configure in-container DNS.
#   - When /run/systemd/resolve/resolv.conf exists and is non-empty, mount it
#     read-only at /etc/resolv.conf
#   - Otherwise, supply public resolvers via --dns flags
#   Example:
#     mapfile -t DNS_ARGS < <(podman_build_dns_args "${DEBUG:-false}")
#     podman run "${DNS_ARGS[@]}" ...
podman_build_dns_args() {
  local debug="${1:-false}"
  local src="/run/systemd/resolve/resolv.conf"
  if [ -r "$src" ] && [ -s "$src" ]; then
    [[ "$debug" == "true" ]] && echo "🧭 DNS: mounting host resolv.conf from $src" >&2
    echo "-v" "$src:/etc/resolv.conf:ro"
  else
    [[ "$debug" == "true" ]] && echo "🧭 DNS: using public resolvers (1.1.1.1, 8.8.8.8)" >&2
    echo "--dns" "1.1.1.1"
    echo "--dns" "8.8.8.8"
  fi
}


# run_with_preview \
#   <container_name> <env_file> <restart_policy> <memory_limit> <image_ref> <extra_run_args> <debug> \
#   <PORT_ARGS[@]> <DNS_ARGS[@]> <NETWORK_ARGS[@]> <LABEL_ARGS[@]>
#   Notes:
#   - Array parameters must be passed as name[@], e.g., PORT_ARGS[@]
#   - <extra_run_args> is a single string; it will be split like the shell would
#   Example:
#     run_with_preview "$CONTAINER_NAME" "$ENV_FILE" "$RESTART_POLICY" "$MEMORY_LIMIT" "$IMAGE_REF" "${EXTRA_RUN_ARGS:-}" "${DEBUG:-false}" \
#       PORT_ARGS[@] DNS_ARGS[@] NETWORK_ARGS[@] LABEL_ARGS[@]
podman_run_with_preview() {
  local name="$1"; shift
  local env_file="$1"; shift
  local restart_policy="$1"; shift
  local memory_limit="$1"; shift
  local image_ref="$1"; shift
  local extra_run_args="$1"; shift
  local debug="$1"; shift

  # Indirect array expansion from names
  local -a port_args dns_args network_args label_args extra_args
  local port_ref="$1"; shift
  local dns_ref="$1"; shift
  local net_ref="$1"; shift
  local label_ref="$1"; shift
  # shellcheck disable=SC1087
  port_args=("${!port_ref}")
  dns_args=("${!dns_ref}")
  network_args=("${!net_ref}")
  label_args=("${!label_ref}")

  # Build command
  local -a cmd=(podman run -d --name "$name" --env-file "$env_file")
  cmd+=("${port_args[@]}")
  cmd+=(--restart="$restart_policy" --memory="$memory_limit" --memory-swap="$memory_limit")
  cmd+=("${dns_args[@]}")
  cmd+=("${network_args[@]}")
  if [[ -n "$extra_run_args" ]]; then
    # shellcheck disable=SC2206
    extra_args=($extra_run_args)
    cmd+=("${extra_args[@]}")
  fi
  cmd+=("${label_args[@]}")
  cmd+=("$image_ref")

  if [[ "$debug" == "true" ]]; then
    echo "🐚 podman run command (preview):"
    printf '  '
    printf '%q ' "${cmd[@]}"
    printf '\n'
  fi

  "${cmd[@]}"
}


# login_if_credentials <registry> <username> <token>
#   Logs into the container registry only when both username and token are
#   provided. Prints a short status message and sets PODMAN_LOGIN_STATUS to one of:
#     logged_in | login_failed | skipped
#   Example:
#     podman_login_if_credentials "$IMAGE_REGISTRY" "$REGISTRY_USERNAME" "$REGISTRY_TOKEN"
podman_login_if_credentials() {
  local registry="$1"
  local username="$2"
  local token="$3"

  if [[ -n "$username" && -n "$token" ]]; then
    echo "🔐 Logging into registry $registry ..."
    if printf '%s' "$token" | podman login "$registry" -u "$username" --password-stdin; then
      PODMAN_LOGIN_STATUS="logged_in"
    else
      PODMAN_LOGIN_STATUS="login_failed"
      export PODMAN_LOGIN_STATUS
      return 1
    fi
  else
    echo "ℹ️  No explicit credentials provided; skipping login"
    PODMAN_LOGIN_STATUS="skipped"
  fi

  export PODMAN_LOGIN_STATUS
  return 0
}

# pull_image <image_ref>
#   Pulls the specified image. Outputs a concise status line prior to pulling.
#   Sets PODMAN_PULL_STATUS to: pulled | pull_failed
#   Example:
#     podman_pull_image "ghcr.io/org/app:tag"
podman_pull_image() {
  local image_ref="$1"
  echo "📥 Pulling image: $image_ref"
  if podman pull "$image_ref"; then
    PODMAN_PULL_STATUS="pulled"
  else
    PODMAN_PULL_STATUS="pull_failed"
    export PODMAN_PULL_STATUS
    return 1
  fi
  export PODMAN_PULL_STATUS
  return 0
}