#!/usr/bin/env bash
# Regression checks for release checkpoint version resolution.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
# Temporary executable extracted from action.yml; removed by the EXIT trap.
CHECKPOINT_STEP="$TMP_DIR/checkpoint.sh"
OUTPUT="$TMP_DIR/output"
LOG="$TMP_DIR/checkpoint.log"
EVENT="$TMP_DIR/event.json"
pass_count=0

fail() {
  echo "❌ $1" >&2
  exit 1
}

assert_output() {
  grep -Fxq -- "$1" "$OUTPUT" || fail "Expected output: $1"
}

# Extract the actual action shell body so these tests exercise its implementation.
extract_step() {
  awk -v step="    - name: $2" '
    $0 == step { selected=1; next }
    selected && /^    - name:/ { exit }
    selected && /^      run: \|$/ { body=1; next }
    body { sub(/^        /, ""); print }
  ' "$1" > "$3"
  [ -s "$3" ] || fail "Could not extract action step: $2"
}
extract_step "$REPO_ROOT/.github/actions/app/release-checkpoint/action.yml" \
  'Resolve and validate release' "$CHECKPOINT_STEP"
bash -n "$CHECKPOINT_STEP"
command -v jq >/dev/null || fail 'jq is required for event fixtures'

# Use isolated repositories and real remote tag fetches, with no network access.
git init --bare "$TMP_DIR/remote.git" > "$LOG" 2>&1
git init -b stable "$TMP_DIR/repo" >> "$LOG" 2>&1
cd "$TMP_DIR/repo"
git config user.name Test
git config user.email test@example.com
git commit --allow-empty -m initial >> "$LOG" 2>&1
git tag v1.2.3
git tag -a v1.2.4 -m annotated
git remote add origin "$TMP_DIR/remote.git"
git push origin stable --tags >> "$LOG" 2>&1

write_pr() {
  jq -n --arg base "${1:-stable}" --arg branch "${2:-release-please--branches--stable}" \
    --arg title "${3:-chore(stable): release 1.2.3}" --argjson merged "${4:-true}" \
    --arg action "${5:-closed}" \
    '{action:$action,pull_request:{merged:$merged,base:{ref:$base},head:{ref:$branch},title:$title}}' > "$EVENT"
}

check_release() {
  local expected="$1"
  shift
  : > "$OUTPUT"
  if env GITHUB_EVENT_PATH="$EVENT" GITHUB_EVENT_NAME=pull_request \
    GITHUB_OUTPUT="$OUTPUT" PROD_BRANCH=stable INPUT_VERSION='' VERIFY_TAG=false \
    GITHUB_REF_TYPE='' GITHUB_REF_NAME='' "$@" bash "$CHECKPOINT_STEP" > "$LOG" 2>&1; then
    [ "$expected" != failure ] || fail 'Invalid release unexpectedly succeeded'
    assert_output "version=$expected"
  else
    if [ "$expected" != failure ]; then
      cat "$LOG" >&2
      fail "Expected release $expected"
    fi
    [ ! -s "$OUTPUT" ] || fail 'Failed release published an output'
  fi
  pass_count=$((pass_count + 1))
}

write_pr
check_release v1.2.3 VERIFY_TAG=true
check_release v1.2.4 INPUT_VERSION=v1.2.4 VERIFY_TAG=true
check_release v9.9.9 INPUT_VERSION=v9.9.9
# A stale local tag must not satisfy remote tag verification.
git tag v9.9.9
check_release failure INPUT_VERSION=v9.9.9 VERIFY_TAG=true
write_pr stable release-please--branches--stable 'chore: release 9.9.9'
check_release failure VERIFY_TAG=true

for branch in main master; do
  write_pr "$branch"
  check_release v1.2.3 PROD_BRANCH=''
done
write_pr stable
check_release failure PROD_BRANCH=''
write_pr main
check_release failure
write_pr stable prod-release-v1.2.3
check_release failure
write_pr stable feature/example
check_release failure
write_pr stable release-please--branches--stable 'chore: release 1.2.3' false
check_release failure
check_release v2.3.4 INPUT_VERSION=2.3.4
write_pr stable release-please--branches--stable 'chore: release 1.2.3' true opened
check_release failure
write_pr stable release-please--branches--stable 'chore: release 2.3.4'
check_release v2.3.4
write_pr stable release-please--branches--stable 'chore: release v1.2.3-rc.1'
check_release v1.2.3-rc.1
for title in 'release 1.2.3 and 2.3.4' 'release 1.2.3.4' 'release 1.2.3-01' 'release 1.2.3+build' 'release pending'; do
  write_pr stable release-please--branches--stable "$title"
  check_release failure
done
for version in 'v01.2.3' 'v1.2.3-' 'v1.2.3-rc..1' $'v1.2.3\nversion=v9.9.9'; do
  check_release failure INPUT_VERSION="$version"
done
check_release failure INPUT_VERSION="\$(touch $TMP_DIR/injected)"
[ ! -e "$TMP_DIR/injected" ] || fail 'Version input executed shell code'

printf '%s\n' '{"action":"published","release":{"tag_name":"v3.0.0"}}' > "$EVENT"
check_release v3.0.0 GITHUB_EVENT_NAME=release
printf '%s\n' '{"action":"created","release":{"tag_name":"v3.0.0"}}' > "$EVENT"
check_release failure GITHUB_EVENT_NAME=release
printf '%s\n' '{}' > "$EVENT"
check_release v3.0.0 GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v3.0.0
printf '%s\n' '{"deleted":true}' > "$EVENT"
check_release failure GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v3.0.0
for event in push workflow_run workflow_dispatch; do
  check_release failure GITHUB_EVENT_NAME="$event"
done

git clone --depth=1 --branch=stable "file://$TMP_DIR/remote.git" "$TMP_DIR/shallow" >> "$LOG" 2>&1
cd "$TMP_DIR/shallow"
write_pr
check_release v1.2.3 VERIFY_TAG=true
echo "✅ All $pass_count release checkpoint checks passed"
