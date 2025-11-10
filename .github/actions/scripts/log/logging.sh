#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# COMMON LOGGING BOOTSTRAP
# -----------------------------------------------------------------------------
# Purpose: initialize structured logging for app deployment scripts. Appends
# start/end markers to the shared diagnostic log and configures traps to capture
# failures automatically.
# -----------------------------------------------------------------------------

set -euo pipefail

LOG_FILE="/tmp/uactions_diag_latest.log"
START_TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

{
  printf '===== %s start %s =====\n' "${RUN_SCRIPT_NAME:-uactions-script}" "$START_TIMESTAMP"
} >> "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'code=$?; printf "%s error exit %s at %s\n" "${RUN_SCRIPT_NAME:-uactions-script}" "$code" "$(date -u "+%Y-%m-%d %H:%M:%S UTC")" >> "$LOG_FILE"; exit "$code"' ERR
trap '{ printf "===== %s end %s =====\n" "${RUN_SCRIPT_NAME:-uactions-script}" "$(date -u "+%Y-%m-%d %H:%M:%S UTC")"; }' EXIT
