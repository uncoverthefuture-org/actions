#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# prune-podman-storage.sh - Safe Podman storage cleanup for uactions hosts
# ----------------------------------------------------------------------------
# Purpose:
#   Reclaim disk space used by unused Podman containers/images/volumes
#   without impacting running workloads. Intended to be called from
#   run-deployment.sh after a successful deploy.
#
# Inputs (environment variables):
#   PODMAN_PRUNE_ENABLED          - When "true", perform cleanup (default: true)
#   PODMAN_PRUNE_MIN_AGE_DAYS     - Minimum age in days before pruning (default: 15)
#   PODMAN_PRUNE_KEEP_RECENT_IMAGES - Reserved for future per-repo retention (default: 2)
#   PODMAN_PRUNE_VOLUMES          - When "true", prune unused volumes (default: false)
#
# Notes:
#   - Only unused resources are pruned. Running containers and images in use
#     are preserved by Podman.
#   - Age-based pruning uses the Docker/Podman-compatible "until" filter,
#     expressed in hours (for example, 360h ≈ 15 days).
# ----------------------------------------------------------------------------
set -euo pipefail

if [ "${PODMAN_PRUNE_ENABLED:-true}" != "true" ]; then
  echo "::notice::PODMAN_PRUNE_ENABLED=${PODMAN_PRUNE_ENABLED:-false}; skipping Podman storage cleanup" >&2
  exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "::notice::podman not found on PATH; skipping Podman storage cleanup" >&2
  exit 0
fi

PODMAN_PRUNE_MIN_AGE_DAYS="${PODMAN_PRUNE_MIN_AGE_DAYS:-15}"
PODMAN_PRUNE_KEEP_RECENT_IMAGES="${PODMAN_PRUNE_KEEP_RECENT_IMAGES:-2}"
PODMAN_PRUNE_VOLUMES="${PODMAN_PRUNE_VOLUMES:-false}"

# Convert days to hours for the until= filter. Example: 15 days → 360h.
if ! printf '%s' "$PODMAN_PRUNE_MIN_AGE_DAYS" | grep -qE '^[0-9]+$'; then
  echo "::warning::PODMAN_PRUNE_MIN_AGE_DAYS=$PODMAN_PRUNE_MIN_AGE_DAYS is not a valid integer; defaulting to 15 days" >&2
  PODMAN_PRUNE_MIN_AGE_DAYS=15
fi
AGE_HOURS=$((PODMAN_PRUNE_MIN_AGE_DAYS * 24))
UNTIL_FILTER="${AGE_HOURS}h"

STORE_ROOT="$(podman info --format '{{ .Store.GraphRoot }}' 2>/dev/null || echo "")"
if [ -n "$STORE_ROOT" ]; then
  echo "================================================================" >&2
  echo "📦 Podman storage before cleanup (df + system df)" >&2
  echo "================================================================" >&2
  df -h "$STORE_ROOT" || df -h || true
  podman system df -v 2>/dev/null || podman system df 2>/dev/null || true
fi

echo "================================================================" >&2
echo "🧹 Pruning stopped containers older than ${PODMAN_PRUNE_MIN_AGE_DAYS} days (until=${UNTIL_FILTER})" >&2
if ! podman container prune --force --filter "until=${UNTIL_FILTER}" >/dev/null 2>&1; then
  echo "::warning::podman container prune with until=${UNTIL_FILTER} failed or unsupported; falling back to simple container prune" >&2
  podman container prune --force >/dev/null 2>&1 || true
fi

echo "================================================================" >&2
echo "🧹 Pruning unused images older than ${PODMAN_PRUNE_MIN_AGE_DAYS} days (until=${UNTIL_FILTER})" >&2
if ! podman image prune --force --filter "until=${UNTIL_FILTER}" >/dev/null 2>&1; then
  echo "::warning::podman image prune with until=${UNTIL_FILTER} failed or unsupported; falling back to simple image prune" >&2
  podman image prune --force >/dev/null 2>&1 || true
fi

echo "PODMAN_PRUNE_KEEP_RECENT_IMAGES=${PODMAN_PRUNE_KEEP_RECENT_IMAGES} (hint only; age filter governs pruning behavior)" >&2

if [ "$PODMAN_PRUNE_VOLUMES" = "true" ]; then
  echo "================================================================" >&2
  echo "🧹 Pruning unused Podman volumes" >&2
  echo "================================================================" >&2
  podman volume prune --force >/dev/null 2>&1 || true
fi

if [ -n "$STORE_ROOT" ]; then
  echo "================================================================" >&2
  echo "📦 Podman storage after cleanup (df + system df)" >&2
  echo "================================================================" >&2
  df -h "$STORE_ROOT" || df -h || true
  podman system df -v 2>/dev/null || podman system df 2>/dev/null || true
fi

exit 0
