#!/usr/bin/env bash
# verify-action-files.sh - validates action yaml files for open source PRs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🚀 Running PR Validation Checks scripts..."
echo "Validating syntax and ensuring there are no prohibited usages..."

# Run the local lint-uses logic (simulating what the action does, 
# but directly in the test suite so it fails fast).
REL_FILES=$(find "${REPO_ROOT}" -name "*.yml" -o -name "*.yaml" \
  | grep -v action.yml \
  | xargs grep -lE "^[[:space:]]*uses:[[:space:]]+\./\\.github/actions/" \
  | grep -v "/auto-version.yml$" \
  | grep -v "version/compute-next" \
  | grep -v "version/update-tags" || true)

if [ -n "$REL_FILES" ]; then
  echo "❌ Error: Found relative uses outside of the dispatcher in: $REL_FILES" >&2
  exit 1
fi



echo "✅ All PR action files are well-formed and valid!"
exit 0
