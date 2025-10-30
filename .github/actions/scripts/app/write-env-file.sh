#!/usr/bin/env bash
# write-env-file.sh - Write environment file to remote server
set -euo pipefail

ENV_FILE_PATH="${ENV_FILE_PATH:-}"
ENV_B64="${ENV_B64:-}"
ENV_CONTENT="${ENV_CONTENT:-}"

if [ -z "$ENV_FILE_PATH" ]; then
  echo "Error: ENV_FILE_PATH is required" >&2
  exit 1
fi

if [ -z "$ENV_B64" ] && [ -z "$ENV_CONTENT" ]; then
  echo "Error: Either ENV_B64 or ENV_CONTENT must be provided" >&2
  exit 1
fi

echo " Preparing to write env file"
echo "  • Target: $ENV_FILE_PATH"
if [ -n "$ENV_B64" ]; then
  echo "  • Source: base64 payload (content will not be printed)"
else
  echo "  • Source: raw content (content will not be printed)"
fi

# Ensure directory exists and is writable by current user
ENV_PARENT_DIR="$(dirname "$ENV_FILE_PATH")"
echo " Ensuring directory exists: $ENV_PARENT_DIR"
if [ -d "$ENV_PARENT_DIR" ] && [ ! -w "$ENV_PARENT_DIR" ]; then
  echo "Error: Directory $ENV_PARENT_DIR is not writable by $(id -un)" >&2
  echo "Hint: adjust ownership (e.g., chown -R $(id -un) $ENV_PARENT_DIR) or choose a user-owned path." >&2
  exit 1
fi
if [ ! -d "$ENV_PARENT_DIR" ]; then
  if ! mkdir -p "$ENV_PARENT_DIR"; then
    echo "Error: Unable to create directory $ENV_PARENT_DIR" >&2
    echo "Hint: ensure the SSH user owns the parent path or select a directory under $HOME." >&2
    exit 1
  fi
fi
if [ ! -w "$ENV_PARENT_DIR" ]; then
  echo "Error: Directory $ENV_PARENT_DIR is not writable by $(id -un)" >&2
  echo "Hint: adjust permissions or choose a user-owned path." >&2
  exit 1
fi

# Decode and write (do not print content for security)
if [ -n "$ENV_B64" ]; then
  printf '%s' "$ENV_B64" | base64 -d > "$ENV_FILE_PATH"
else
  printf '%s' "$ENV_CONTENT" > "$ENV_FILE_PATH"
fi

# Set permissions
chmod 600 "$ENV_FILE_PATH"

echo " Environment file written to $ENV_FILE_PATH (600)"
echo "" 
ls -lh "$ENV_FILE_PATH"
