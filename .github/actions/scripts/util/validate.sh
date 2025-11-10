#!/bin/bash

# Function to validate required keys in an associative array
validate_required() {
  declare -n kv_pairs=$1
  shift
  local missing=()

  for key in "$@"; do
    if [[ -z "${kv_pairs[$key]}" ]]; then
      missing+=("$key")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Error: ${missing[*]} are required." >&2
    exit 1
  fi
}
