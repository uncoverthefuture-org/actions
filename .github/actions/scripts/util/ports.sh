# shellcheck shell=bash
# -----------------------------------------------------------------------------
# ports.sh - Shared port utility helpers
# -----------------------------------------------------------------------------
# Purpose:
#   Provide reusable Bash helpers for validating ports, checking whether a port
#   is currently bound, and finding the next available port within a range.
# -----------------------------------------------------------------------------

# validate_port_number <port>
#   Returns success when <port> is an integer within 1-65535.
validate_port_number() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

# port_in_use <port>
#   Returns success when <port> appears to be in use. Uses whichever inspection
#   tool is available (ss, lsof, netstat). Falls back to failure when no tool
#   can confirm usage.
port_in_use() {
  local port="$1"
  if ! validate_port_number "$port"; then
    return 1
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -q -E "(:|^)$port$"; then
      return 0
    fi
  fi

  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v netstat >/dev/null 2>&1; then
    if netstat -tln 2>/dev/null | awk '{print $4}' | grep -q -E "(:|^)$port$"; then
      return 0
    fi
  fi

  return 1
}

# find_available_port <start> [max_attempts]
#   Emits the first port >= <start> that is not currently in use.
#   max_attempts defaults to 100 when omitted.
find_available_port() {
  local start="$1"
  local limit="${2:-100}"

  if ! validate_port_number "$start"; then
    echo "::error::find_available_port start port must be between 1-65535" >&2
    return 1
  fi

  local port="$start"
  local attempts=0
  while (( port <= 65535 && attempts <= limit )); do
    if ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
    port=$(( port + 1 ))
    attempts=$(( attempts + 1 ))
  done

  echo "::error::Unable to locate free port after $limit attempts starting at $start" >&2
  return 1
}
