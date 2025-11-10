#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# podman_run.sh - Assemble and execute podman run with a DEBUG preview
# -----------------------------------------------------------------------------
# Purpose:
#   Provide a reusable wrapper that builds a `podman run` command from
#   structured inputs (scalars + argument arrays), prints a safely-quoted
#   preview when DEBUG=true, and then executes it.
# -----------------------------------------------------------------------------

# run_with_preview \
#   <container_name> <env_file> <restart_policy> <memory_limit> <image_ref> <extra_run_args> <debug> \
#   <PORT_ARGS[@]> <DNS_ARGS[@]> <NETWORK_ARGS[@]> <LABEL_ARGS[@]>
#   Notes:
#   - Array parameters must be passed as name[@], e.g., PORT_ARGS[@]
#   - <extra_run_args> is a single string; it will be split like the shell would
#   Example:
#     run_with_preview "$CONTAINER_NAME" "$ENV_FILE" "$RESTART_POLICY" "$MEMORY_LIMIT" "$IMAGE_REF" "${EXTRA_RUN_ARGS:-}" "${DEBUG:-false}" \
#       PORT_ARGS[@] DNS_ARGS[@] NETWORK_ARGS[@] LABEL_ARGS[@]
run_with_preview() {
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
