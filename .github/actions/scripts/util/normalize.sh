# shellcheck shell=bash
# -----------------------------------------------------------------------------
# normalize.sh - String normalization helpers
# -----------------------------------------------------------------------------
# Purpose:
#   Provide reusable Bash helpers for normalizing strings to lowercase,
#   useful for container registries like GHCR that enforce lowercase paths.
# -----------------------------------------------------------------------------

# normalize_string <string> [description]
#   Converts the input string to lowercase. Emits a notice when DEBUG=true and
#   the value changed. The optional description is included in the debug message.
#   Prints the normalized string to stdout.
#   Example:
#     normalize_string "GHCR.IO/MyApp" "image name"  # -> ghcr.io/myapp
normalize_string() {
  local str="$1"
  local desc="${2:-value}"
  local normalized

  if [[ -z "$str" ]]; then
    return 0
  fi

  normalized=$(printf '%s' "$str" | tr '[:upper:]' '[:lower:]')
  if [[ "${DEBUG:-false}" == "true" && "$str" != "$normalized" ]]; then
    echo "🔤 Normalized $desc to lowercase: $normalized"
  fi
  printf '%s' "$normalized"
}