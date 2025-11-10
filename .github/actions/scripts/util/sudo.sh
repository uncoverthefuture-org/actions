#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# sudo.sh - Helpers for inspecting sudo availability
# -----------------------------------------------------------------------------
# Purpose:
#   Determine whether the current user can invoke sudo without interactive
#   password prompts. Useful for tailoring deployment steps that optionally
#   elevate privileges (e.g., verifying low-port bindings or installing
#   system packages).
# -----------------------------------------------------------------------------

# detect_sudo_status [true_case] [false_case]
#   Echoes which message should be used when sudo is (or is not) available.
#   The optional arguments let callers override the default "available" /
#   "not available" wording without duplicating the detection logic.
#   Returns 0 regardless of result so it can be used in command substitutions.
#   Example:
#     # Prints "available" or "not available" and stores it in SUDO_STATUS.
#     SUDO_STATUS="$(detect_sudo_status)"
#
#     # Custom wording (returns "✅" when sudo works, otherwise "❌").
#     detect_sudo_status "✅" "❌"
#
#   Note: Detection uses `sudo -n true` to avoid blocking on password prompts.
#   If sudo is not installed or passwordless sudo is denied, the false_case is
#   emitted.

detect_sudo_status() {
  local true_case="${1:-available}"
  local false_case="${2:-not available}"

  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    printf '%s' "$true_case"
  else
    printf '%s' "$false_case"
  fi
}
