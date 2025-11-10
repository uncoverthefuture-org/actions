#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# dns.sh - Build DNS-related runtime args for containers
# -----------------------------------------------------------------------------
# Purpose:
#   Standardize how we pass resolver configuration into containers. Prefer the
#   host's systemd-resolved configuration when available, falling back to
#   public resolvers when necessary.
# -----------------------------------------------------------------------------

# build_dns_args [debug]
#   Emits arguments suitable for `podman run` to configure in-container DNS.
#   - When /run/systemd/resolve/resolv.conf exists and is non-empty, mount it
#     read-only at /etc/resolv.conf
#   - Otherwise, supply public resolvers via --dns flags
#   Example:
#     mapfile -t DNS_ARGS < <(build_dns_args "${DEBUG:-false}")
#     podman run "${DNS_ARGS[@]}" ...
build_dns_args() {
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
