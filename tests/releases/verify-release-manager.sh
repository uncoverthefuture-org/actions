#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'chmod -R u+w "$TMP_DIR"; rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home"
export MOCK_ROOT="$TMP_DIR/mock"
mkdir -p "$MOCK_ROOT"
cat > "$TMP_DIR/bin/podman" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ROOT/calls"
case "$1 $2" in
  'inspect traefik')
    [[ "${MOCK_NO_PROXY:-false}" != true ]] || exit 1
    jq -n --arg dynamic "$TRAEFIK_DYNAMIC_DIR" '[{State:{Running:true},Mounts:[{Source:$dynamic,Destination:"/etc/traefik/dynamic"}],NetworkSettings:{Networks:{"traefik-network":{}}}}]';;
  'image inspect')
    if [[ "$*" == *Healthcheck* ]]; then if [[ "${MOCK_NO_HEALTH:-false}" == true ]]; then echo null; else echo '{"Test":["CMD","true"]}'; fi; else printf 'sha256:%064d\n' "${MOCK_IMAGE:-1}"; fi;;
  'container exists') [[ -f "$MOCK_ROOT/$3" ]];;
  'save --format') while (($#)); do if [[ "$1" == --output ]]; then printf archive > "$2"; break; fi; shift; done;;
  'load --input') test -s "$3";;
  'inspect --format')
    if [[ "${MOCK_UNHEALTHY:-false}" == true && "$(cat "$MOCK_ROOT/${@: -1}")" == *0002 ]]; then echo '{"Status":"exited"}'; else echo '{"Status":"running","Health":{"Status":"healthy"}}'; fi;;
  'run -d')
    name=''; previous=''
    for arg in "$@"; do [[ "$previous" != --name ]] || name="$arg"; previous="$arg"; done
    printf '%s' "${@: -1}" > "$MOCK_ROOT/$name";;
  'stop --time') touch "$MOCK_ROOT/${@: -1}.stopped";;
  'rm --force') rm -f "$MOCK_ROOT/${@: -1}";;
  *) echo "unexpected podman call: $*" >&2; exit 1;;
esac
MOCK
chmod +x "$TMP_DIR/bin/podman"
export PATH="$TMP_DIR/bin:$PATH"
source "$REPO_ROOT/.github/actions/scripts/app/release-manager.sh"
export QUADLET_ENABLED=false
ROOT="$TMP_DIR/home/releases"
ENV_FILE="$TMP_DIR/app.env"
printf 'TOKEN=first\n' > "$ENV_FILE"
release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" -v "$ENV_FILE:/app/.env:ro" --memory 512m image:v1
FIRST=$(jq -r .current "$ROOT/state.json")
test "$(cat "$ROOT/releases/$FIRST/.env")" = TOKEN=first
jq -e --arg env "$ROOT/releases/$FIRST/.env" '.argv | index($env) != null' "$ROOT/releases/$FIRST/release.json" >/dev/null
printf 'TOKEN=second\n' > "$ENV_FILE"
export MOCK_IMAGE=2
release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" --memory 1g image:v2
SECOND=$(jq -r .current "$ROOT/state.json")
test "$FIRST" != "$SECOND"
test "$(cat "$ROOT/releases/$FIRST/.env")" = TOKEN=first
test "$(jq -r .previous "$ROOT/state.json")" = "$FIRST"
release_rollback "$ROOT" previous
test "$(jq -r .current "$ROOT/state.json")" = "$FIRST"
test "$(jq -r .previous "$ROOT/state.json")" = "$SECOND"
export MOCK_UNHEALTHY=true
if release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" image:v2; then echo 'unhealthy release was accepted' >&2; exit 1; fi
test "$(jq -r .current "$ROOT/state.json")" = "$FIRST"
test "$(cat "$MOCK_ROOT/sample")" = "$(jq -r .image "$ROOT/releases/$FIRST/release.json")"
test ! -d "$ROOT/.lock"
mkdir "$ROOT/.lock"
if release_rollback "$ROOT" previous; then echo 'lock was bypassed' >&2; exit 1; fi
rmdir "$ROOT/.lock"
if release_rollback "$ROOT" ../escape; then echo 'unsafe id was accepted' >&2; exit 1; fi
export MOCK_NO_HEALTH=true
if release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" image:v2; then echo 'missing healthcheck accepted' >&2; exit 1; fi
unset MOCK_NO_HEALTH
test "$(jq -r .current "$ROOT/state.json")" = "$FIRST"
test "$(cat "$MOCK_ROOT/sample")" = "$(jq -r .image "$ROOT/releases/$FIRST/release.json")"
# Every user argument is serialized literally, including spaces and shell syntax.
export MOCK_IMAGE=3
printf 'TOKEN=third\n' > "$ENV_FILE"
release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" --label 'literal=$(touch unexpected)' image:v3
THIRD=$(jq -r .current "$ROOT/state.json")
jq -e '.argv | index("literal=$(touch unexpected)") != null' "$ROOT/releases/$THIRD/release.json" >/dev/null
test ! -e unexpected
release_rollback "$ROOT" v1
# An arbitrary/missing image tag must not fall back to the registry.
if release_rollback "$ROOT" missing-tag; then echo 'unknown tag accepted' >&2; exit 1; fi
# A repeated successful image tag selects the newest configuration snapshot.
export MOCK_IMAGE=4
printf 'TOKEN=updated-v1\n' > "$ENV_FILE"
release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" image:v1
NEW_FIRST=$(jq -r .current "$ROOT/state.json")
release_rollback "$ROOT" v3
release_rollback "$ROOT" v1
test "$(jq -r .current "$ROOT/state.json")" = "$NEW_FIRST"
test "$(cat "$ROOT/releases/$NEW_FIRST/.env")" = TOKEN=updated-v1
# A failed redeployment of the same tag must not replace the successful lookup.
export MOCK_IMAGE=2
if release_deploy "$ROOT" "$ENV_FILE" podman run -d --name sample --env-file "$ENV_FILE" image:v1; then echo 'failed duplicate tag activated' >&2; exit 1; fi
release_rollback "$ROOT" v1
test "$(jq -r .current "$ROOT/state.json")" = "$NEW_FIRST"
# Mutating captured configuration invalidates a release before any switch.
chmod u+w "$ROOT/releases/$SECOND/.env"
printf 'TOKEN=tampered\n' > "$ROOT/releases/$SECOND/.env"
if release_rollback "$ROOT" v2; then echo 'tampered release was accepted' >&2; exit 1; fi
test "$(jq -r .current "$ROOT/state.json")" = "$NEW_FIRST"
bash -n "$ROOT/releases/$FIRST/start.sh"
# Exercise actual setup, action output and runner rollback with the default path.
(
  export HOME="$TMP_DIR/path-home" ENV_FILE_PATH_BASE='~/deployments'
  export APP_SLUG=path-app ENV_NAME=production RELEASE_SNAPSHOTS=true
  export DEPLOYMENT_STRATEGY=recreate MOCK_UNHEALTHY=false MOCK_IMAGE=1
  export ENV_B64='' ENV_CONTENT='' DEBUG=false
  unset RELEASE_ROOT REMOTE_DEPLOYMENT_DIR REMOTE_ENV_DIR REMOTE_ENV_FILE
  mkdir -p "$HOME"
  # Avoid using host sudo while exercising the real directory setup script.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP_DIR/bin/sudo"
  chmod +x "$TMP_DIR/bin/sudo"
  source "$REPO_ROOT/.github/actions/scripts/app/setup-env-file.sh"
  expected="$HOME/deployments/production/path-app/managed"
  test "$RELEASE_ROOT" = "$expected"
  test ! -e "$HOME/~"
  release_deploy "$RELEASE_ROOT" "$REMOTE_ENV_FILE" podman run -d --name path-app -p 8081:3000 --env-file "$REMOTE_ENV_FILE" image:path-v1
  first=$(jq -r .current "$RELEASE_ROOT/state.json")
  # Extract the SSH action's real remote port-reader body.
  awk '
    /<<\047EOF_PORT\047/ { selected=1; next }
    selected && /^        EOF_PORT$/ { exit }
    selected { sub(/^        /, ""); print }
  ' "$REPO_ROOT/.github/actions/app/ssh-container-deploy/action.yml" > "$TMP_DIR/port-reader.sh"
  test -s "$TMP_DIR/port-reader.sh"
  read_port() { bash "$TMP_DIR/port-reader.sh" "$ENV_FILE_PATH_BASE" "$ENV_NAME" "$APP_SLUG" true; }
  # Stale legacy metadata must never override committed managed state.
  printf '9999\n' > "$HOME/deployments/production/path-app/.host-port"
  test "$(read_port)" = 8081
  export MOCK_IMAGE=3
  release_deploy "$RELEASE_ROOT" "$REMOTE_ENV_FILE" podman run -d --name path-app -p 8082:3000 --env-file "$REMOTE_ENV_FILE" image:path-v2
  test "$(read_port)" = 8082
  export MOCK_IMAGE=2 MOCK_UNHEALTHY=true
  if release_deploy "$RELEASE_ROOT" "$REMOTE_ENV_FILE" podman run -d --name path-app -p 8083:3000 --env-file "$REMOTE_ENV_FILE" image:path-failed; then
    echo 'unhealthy candidate changed committed port' >&2; exit 1
  fi
  test "$(read_port)" = 8082
  export MOCK_UNHEALTHY=false ROLLBACK_VERSION=path-v1
  unset RELEASE_ROOT
  bash "$REPO_ROOT/.github/actions/scripts/app/run-deployment.sh"
  test "$(jq -r .current "$expected/state.json")" = "$first"
  test "$(read_port)" = 8081
  # Custom bases, including spaces, use the same output reader.
  custom="$HOME/custom releases"
  mkdir -p "$custom/production/path-app/managed"
  cp "$expected/state.json" "$custom/production/path-app/managed/state.json"
  test "$(bash "$TMP_DIR/port-reader.sh" "$custom" production path-app true)" = 8081
  test "$(bash "$TMP_DIR/port-reader.sh" '~/deployments' production path-app false)" = 9999
)

# Exercise the real action's validation without connecting to any remote host.
awk '
  /^    - name: Validate release options$/ { selected=1; next }
  selected && /^    - name:/ { exit }
  selected && /^      run: \|$/ { body=1; next }
  body { sub(/^        /, ""); print }
' "$REPO_ROOT/.github/actions/app/common/release-options/action.yml" > "$TMP_DIR/options.sh"
for enabled in true false; do
  env RELEASE_SNAPSHOTS="$enabled" ROLLBACK_VERSION='' GITHUB_OUTPUT="$TMP_DIR/options-output" bash "$TMP_DIR/options.sh"
done
if env RELEASE_SNAPSHOTS=false ROLLBACK_VERSION=previous GITHUB_OUTPUT="$TMP_DIR/options-output" bash "$TMP_DIR/options.sh"; then echo 'unmanaged rollback accepted' >&2; exit 1; fi
if env RELEASE_SNAPSHOTS=true ROLLBACK_VERSION='../escape' GITHUB_OUTPUT="$TMP_DIR/options-output" bash "$TMP_DIR/options.sh"; then echo 'invalid action release id accepted' >&2; exit 1; fi
# Mock only infrastructure. Promotion/recovery use the real route writer and
# verification loop, and inspect its emitted routing configuration.
cat > "$TMP_DIR/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
headers=''
while (($#)); do
  if [[ "$1" == --dump-header ]]; then headers="$2"; shift; fi
  shift
done
route="$TRAEFIK_DYNAMIC_DIR/uactions-bg-router.json"
name=$(jq -r '.http.services["bg-router"].loadBalancer.servers[0].url' "$route")
name=${name#http://}; name=${name%:*}
if [[ "${MOCK_ROUTE_FAIL:-false}" == true && "$(cat "$MOCK_ROOT/$name")" == *0005 ]]; then exit 22; fi
id=$(jq -r '.http.middlewares["bg-router-release"].headers.customResponseHeaders["X-UActions-Release"]' "$route")
printf 'HTTP/1.1 200 OK\r\nX-UActions-Release: %s\r\n' "$id" > "$headers"
printf 'route %s\n' "$name" >> "$MOCK_ROOT/calls"
CURL
cat > "$TMP_DIR/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "$TMP_DIR/bin/curl" "$TMP_DIR/bin/sleep"
export TRAEFIK_DYNAMIC_DIR="$TMP_DIR/dynamic"
mkdir "$TRAEFIK_DYNAMIC_DIR"
export DEPLOYMENT_STRATEGY=blue-green TRAEFIK_ENABLED=true ROUTER_NAME=bg-router
export DOMAIN=example.com CONTAINER_PORT=3000 TRAEFIK_ENABLE_ACME=false READINESS_PATH=/health
BG_ROOT="$TMP_DIR/bg"
export MOCK_IMAGE=3
release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' --label traefik.enable=true image:blue
BLUE=$(jq -r .current "$BG_ROOT/state.json")
BLUE_NAME=$(jq -r .container "$BG_ROOT/releases/$BLUE/release.json")
jq -e '.strategy == "blue-green" and ([.argv[] | select(startswith("traefik."))] == ["traefik.enable=false"])' "$BG_ROOT/releases/$BLUE/release.json" >/dev/null
export MOCK_IMAGE=4
release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:green
GREEN=$(jq -r .current "$BG_ROOT/state.json")
GREEN_NAME=$(jq -r .container "$BG_ROOT/releases/$GREEN/release.json")
test "$BLUE_NAME" != "$GREEN_NAME"
test -f "$MOCK_ROOT/$BLUE_NAME"
test ! -f "$MOCK_ROOT/$BLUE_NAME.stopped"
test "$(jq -r '.http.middlewares["bg-router-release"].headers.customResponseHeaders["X-UActions-Release"]' "$TRAEFIK_DYNAMIC_DIR/uactions-bg-router.json")" = "$GREEN"
release_rollback "$BG_ROOT" blue
test "$(jq -r .current "$BG_ROOT/state.json")" = "$BLUE"
test -f "$MOCK_ROOT/$GREEN_NAME"
# A healthy container with a failing public readiness route must restore traffic
# and leave the committed active release unchanged.
export MOCK_IMAGE=5 MOCK_ROUTE_FAIL=true
if release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:broken-route; then echo 'broken public route accepted' >&2; exit 1; fi
test "$(jq -r .current "$BG_ROOT/state.json")" = "$BLUE"
test "$(jq -r '.http.middlewares["bg-router-release"].headers.customResponseHeaders["X-UActions-Release"]' "$TRAEFIK_DYNAMIC_DIR/uactions-bg-router.json")" = "$BLUE"
if release_rollback "$BG_ROOT" broken-route; then echo 'failed blue-green release indexed' >&2; exit 1; fi
# Published ports would collide with the live release and must be rejected.
if release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app -p 3000:3000 --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:invalid; then echo 'published port accepted' >&2; exit 1; fi
# Candidate startup failure must not touch the stable route or live container.
export MOCK_IMAGE=2
if release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:unhealthy; then echo 'unhealthy candidate accepted' >&2; exit 1; fi
test "$(jq -r .current "$BG_ROOT/state.json")" = "$BLUE"
test ! -f "$MOCK_ROOT/$BLUE_NAME.stopped"
export MOCK_IMAGE=6
release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:third
THIRD_BG=$(jq -r .current "$BG_ROOT/state.json")
test "$(jq -r .previous "$BG_ROOT/state.json")" = "$BLUE"
test -f "$MOCK_ROOT/$GREEN_NAME.stopped"
test ! -f "$MOCK_ROOT/$BLUE_NAME.stopped"
export MOCK_NO_PROXY=true
if release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com")' image:no-proxy; then echo 'missing proxy accepted' >&2; exit 1; fi
unset MOCK_NO_PROXY
test "$(jq -r .current "$BG_ROOT/state.json")" = "$THIRD_BG"
# Replay a TLS snapshot's route settings, including host aliases and redirects.
export TRAEFIK_ENABLE_ACME=true
release_deploy "$BG_ROOT" "$ENV_FILE" podman run -d --name bg-app --env-file "$ENV_FILE" --network traefik-network \
  --label 'traefik.http.routers.bg-router.rule=Host("example.com") || Host("www.example.com")' image:tls
jq -e '.http.routers["bg-router"].tls.certResolver == "letsencrypt" and .http.middlewares["bg-router-redirect"].redirectScheme.scheme == "https"' "$TRAEFIK_DYNAMIC_DIR/uactions-bg-router.json" >/dev/null
release_rollback "$BG_ROOT" blue
jq -e '.http.routers["bg-router"].tls == null and .http.routers["bg-router"].entryPoints == ["web"]' "$TRAEFIK_DYNAMIC_DIR/uactions-bg-router.json" >/dev/null
if env DEPLOYMENT_STRATEGY=canary RELEASE_SNAPSHOTS=false ROLLBACK_VERSION='' GITHUB_OUTPUT="$TMP_DIR/options-output" bash "$TMP_DIR/options.sh"; then echo 'unsupported strategy accepted' >&2; exit 1; fi
env DEPLOYMENT_STRATEGY=blue-green RELEASE_SNAPSHOTS=false ROLLBACK_VERSION='' GITHUB_OUTPUT="$TMP_DIR/options-output" bash "$TMP_DIR/options.sh"
grep -Fxq enabled=true "$TMP_DIR/options-output"
unset DEPLOYMENT_STRATEGY
echo 'Release snapshot, rollback, failed promotion recovery, lock and integrity and blue-green checks passed'
