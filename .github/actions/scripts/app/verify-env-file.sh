#!/usr/bin/env bash
# verify-env-file.sh - Verify that the environment file on disk matches the provided payload
#
# Usage:
#   ENV_FILE_PATH="/path/to/.env"
#   ENV_B64="base64-encoded-content"
#   # OR
#   ENV_CONTENT="raw-content"
#   ./verify-env-file.sh
#
# Exit codes:
#   0 - Verification successful (match)
#   1 - Verification failed (mismatch or IO error)

set -euo pipefail

ENV_FILE_PATH="${ENV_FILE_PATH:-}"
ENV_B64="${ENV_B64:-}"
ENV_CONTENT="${ENV_CONTENT:-}"

if [ -z "$ENV_FILE_PATH" ]; then
  echo "Error: ENV_FILE_PATH is required for verification" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE_PATH" ]; then
  echo "::error::Environment file missing at $ENV_FILE_PATH" >&2
  exit 1
fi

# Create a temporary file to hold the expected content for comparison
EXPECTED_TMP="$(mktemp)"
trap 'rm -f "$EXPECTED_TMP"' EXIT

if [ -n "$ENV_B64" ]; then
  # Decode base64 payload to temp file
  if ! printf '%s' "$ENV_B64" | base64 -d > "$EXPECTED_TMP" 2>/dev/null; then
    echo "::error::Failed to decode ENV_B64 for verification" >&2
    exit 1
  fi
elif [ -n "$ENV_CONTENT" ]; then
  # Write raw content to temp file
  printf '%s' "$ENV_CONTENT" > "$EXPECTED_TMP"
else
  # No payload provided; nothing to verify against (or existing file is accepted as-is)
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "ℹ️  No ENV_B64/ENV_CONTENT provided; skipping strict content verification"
  fi
  exit 0
fi

# Sanitize the expected content the same way setup-env-file.sh does to ensure fair comparison
# (setup-env-file.sh might have added quotes to values with spaces)
# However, a simpler, stricter check is to verify that the key-values we *expect* are present.
# But the user asked for "identical".
# Let's check md5sum first. If the setup-env-file.sh modifies the file (sanitization), strict identity might fail.
#
# Wait, setup-env-file.sh does:
# 1. Writes content to .env
# 2. Reads .env, quotes values with spaces, writes to .env.sanitized, moves back to .env
#
# So the file on disk is the SANITIZED version. We need to compare against that.
# To do this robustly without duplicating the sanitization logic here, we should rely on the fact that
# if we just wrote it, it should be fresh.
#
# Actually, the user said: "check the server .env and make sure that it is identical with the env provided... once the base64 is updated it must update the .env"
#
# If `setup-env-file.sh` modifies the content (by quoting), checking against the *original* input will fail.
# We should probably run the same sanitization logic on our expected content before comparing.

# Re-implementing minimal sanitization logic for the expected comparison
SANITIZED_EXPECTED="$(mktemp)"
trap 'rm -f "$EXPECTED_TMP" "$SANITIZED_EXPECTED"' EXIT

while IFS= read -r line || [ -n "$line" ]; do
  # Pass through empty lines, comments, and already-quoted lines
  case "$line" in
    ''|\#*|*\'*|*\"*)
      printf '%s\n' "$line"
      continue
      ;;
  esac

  # Split into KEY and VALUE
  key="${line%%=*}"
  value="${line#*=}"

  if [ "$key" = "$line" ]; then
    printf '%s\n' "$line"
    continue
  fi

  # Check for special chars needing quotes
  needs_quote=false
  case "$value" in
    *\ *|*\	*|*\$*|*\`*|*\!*|*\(*|*\)*|*\;*|*\&*|*\|*|*\<*|*\>*|*\"*|*\'*)
      needs_quote=true
      ;;
  esac

  if $needs_quote; then
    # Escape quotes/slashes
    escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '%s="%s"\n' "$key" "$escaped_value"
  else
    printf '%s\n' "$line"
  fi
done < "$EXPECTED_TMP" > "$SANITIZED_EXPECTED"

# Normalize permissons for comparison (avoid perm diffs causing diff failure if we used diff)
# checking diff content

echo "🔍 Verifying environment file content..."

# Use diff to compare. It's available on most minimal Ubuntu images.
if diff -q "$SANITIZED_EXPECTED" "$ENV_FILE_PATH" >/dev/null; then
  echo "✅ Environment file verification passed (content matches)."
  exit 0
else
  echo "::error::Environment file verification FAILED." >&2
  echo "   The file on disk ($ENV_FILE_PATH) does not match the provided payload." >&2
  echo "   Differences (expected vs actual):" >&2
  # print diff but mask values? No, diff might leak secrets.
  # outputting plain error is safer.
  echo "   [diff output suppressed for security]" >&2
  exit 1
fi
