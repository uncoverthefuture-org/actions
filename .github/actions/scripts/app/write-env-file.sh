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

# Ensure directory exists
echo " Ensuring directory exists: $(dirname "$ENV_FILE_PATH")"
mkdir -p "$(dirname "$ENV_FILE_PATH")"

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
