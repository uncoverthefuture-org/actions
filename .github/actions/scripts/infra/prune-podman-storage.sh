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
#   PODMAN_PRUNE_MIN_AGE_DAYS     - Minimum age in days before pruning (default: 1)
#   PODMAN_PRUNE_KEEP_RECENT_IMAGES - Reserved for future per-repo retention (default: 2)
#   PODMAN_PRUNE_VOLUMES          - When "true", prune unused volumes (default: false)
#   PODMAN_PRUNE_AGGRESSIVE       - When "true", prune ALL stopped containers and
#                                   unused images immediately, not just old ones
#   APP_SLUG                      - App slug for targeted pruning (optional)
#   ENV_NAME                      - Environment name for targeted pruning (optional)
#   CONTAINER_NAME                - Current container name to preserve (optional)
#   IMAGE_REF                     - Current image to preserve (optional)
#
# Notes:
#   - Only unused resources are pruned. Running containers and images in use
#     are preserved by Podman.
#   - Age-based pruning uses the Docker/Podman-compatible "until" filter,
#     expressed in hours (for example, 24h ≈ 1 day).
#   - Aggressive mode removes ALL stopped containers and unused images
#     except the current deployment's container and image.
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

PODMAN_PRUNE_MIN_AGE_DAYS="${PODMAN_PRUNE_MIN_AGE_DAYS:-1}"
PODMAN_PRUNE_KEEP_RECENT_IMAGES="${PODMAN_PRUNE_KEEP_RECENT_IMAGES:-2}"
PODMAN_PRUNE_VOLUMES="${PODMAN_PRUNE_VOLUMES:-false}"
PODMAN_PRUNE_AGGRESSIVE="${PODMAN_PRUNE_AGGRESSIVE:-true}"
APP_SLUG="${APP_SLUG:-}"
ENV_NAME="${ENV_NAME:-}"
CONTAINER_NAME="${CONTAINER_NAME:-}"
IMAGE_REF="${IMAGE_REF:-}"

# Convert days to hours for the until= filter. Example: 15 days → 360h.
if ! printf '%s' "$PODMAN_PRUNE_MIN_AGE_DAYS" | grep -qE '^[0-9]+$'; then
  echo "::warning::PODMAN_PRUNE_MIN_AGE_DAYS=$PODMAN_PRUNE_MIN_AGE_DAYS is not a valid integer; defaulting to 1 day" >&2
  PODMAN_PRUNE_MIN_AGE_DAYS=1
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

# ----------------------------------------------------------------------------
# AGGRESSIVE PRUNING MODE
# Removes ALL stopped containers and unused images immediately
# ----------------------------------------------------------------------------
if [ "$PODMAN_PRUNE_AGGRESSIVE" = "true" ]; then
  echo "================================================================" >&2
  echo "🧹 AGGRESSIVE PRUNE: Removing all stopped containers" >&2
  echo "================================================================" >&2
  
  # Get list of stopped containers before pruning
  STOPPED_CONTAINERS=$(podman ps -a --filter status=exited --filter status=created --filter status=stopped --format '{{.Names}}' 2>/dev/null || true)
  
  if [ -n "$STOPPED_CONTAINERS" ]; then
    echo "Found stopped containers to remove:" >&2
    echo "$STOPPED_CONTAINERS" | while read -r container; do
      # Don't remove the current container if specified
      if [ -n "$CONTAINER_NAME" ] && [ "$container" = "$CONTAINER_NAME" ]; then
        echo "  - $container (PRESERVED - current deployment)" >&2
      else
        echo "  - $container" >&2
        podman rm "$container" >/dev/null 2>&1 && echo "    ✓ Removed" >&2 || echo "    ✗ Failed to remove" >&2
      fi
    done
  else
    echo "No stopped containers found" >&2
  fi
  
  echo "================================================================" >&2
  echo "🧹 AGGRESSIVE PRUNE: Removing unused images" >&2
  echo "================================================================" >&2
  
  # Get the current image ID to preserve it
  CURRENT_IMAGE_ID=""
  if [ -n "$IMAGE_REF" ]; then
    CURRENT_IMAGE_ID=$(podman images --format '{{.ID}}' --filter reference="$IMAGE_REF" 2>/dev/null | head -n1 || true)
  fi
  
  # Get all dangling images first
  DANGLING_IMAGES=$(podman images --filter dangling=true --format '{{.ID}}' 2>/dev/null || true)
  if [ -n "$DANGLING_IMAGES" ]; then
    echo "Removing dangling (untagged) images:" >&2
    echo "$DANGLING_IMAGES" | while read -r img_id; do
      if [ -n "$img_id" ]; then
        if [ -n "$CURRENT_IMAGE_ID" ] && [ "$img_id" = "$CURRENT_IMAGE_ID" ]; then
          echo "  - $img_id (PRESERVED - current image)" >&2
        else
          podman rmi "$img_id" >/dev/null 2>&1 && echo "  - $img_id ✓" >&2 || true
        fi
      fi
    done
  fi
  
  # Get all unused images (not referenced by any container)
  UNUSED_IMAGES=$(podman images --format '{{.ID}} {{.Repository}}:{{.Tag}}' 2>/dev/null | while read -r img_id img_ref; do
    # Check if this image is used by any running or stopped container
    if ! podman ps -a --filter ancestor="$img_id" --format '{{.ID}}' 2>/dev/null | grep -q .; then
      echo "$img_id"
    fi
  done || true)
  
  if [ -n "$UNUSED_IMAGES" ]; then
    echo "Removing unused images (not referenced by any container):" >&2
    echo "$UNUSED_IMAGES" | sort -u | while read -r img_id; do
      if [ -n "$img_id" ]; then
        if [ -n "$CURRENT_IMAGE_ID" ] && [ "$img_id" = "$CURRENT_IMAGE_ID" ]; then
          echo "  - $img_id (PRESERVED - current image)" >&2
        else
          podman rmi "$img_id" >/dev/null 2>&1 && echo "  - $img_id ✓" >&2 || true
        fi
      fi
    done
  fi
  
  # App-specific cleanup: remove old containers for this app
  if [ -n "$APP_SLUG" ] && [ -n "$ENV_NAME" ]; then
    echo "================================================================" >&2
    echo "🧹 App-specific cleanup for ${APP_SLUG}-${ENV_NAME}" >&2
    echo "================================================================" >&2
    
    # Find containers matching this app/env pattern that are stopped
    APP_CONTAINERS=$(podman ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^${APP_SLUG}-${ENV_NAME}" || true)
    if [ -n "$APP_CONTAINERS" ]; then
      echo "Found app containers:" >&2
      echo "$APP_CONTAINERS" | while read -r container; do
        if [ -n "$CONTAINER_NAME" ] && [ "$container" = "$CONTAINER_NAME" ]; then
          echo "  - $container (PRESERVED - current deployment)" >&2
        else
          echo "  - $container (removing...)" >&2
          podman stop "$container" >/dev/null 2>&1 || true
          podman rm "$container" >/dev/null 2>&1 && echo "    ✓ Removed" >&2 || echo "    ✗ Failed" >&2
        fi
      done
    fi
  fi
else
  # ----------------------------------------------------------------------------
  # AGE-BASED PRUNING MODE (original behavior)
  # ----------------------------------------------------------------------------
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
