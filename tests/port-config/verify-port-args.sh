#!/usr/bin/env bash
# verify-port-args.sh - regression checks for container port handling
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_SCRIPT="$REPO_ROOT/.github/actions/scripts/app/deploy-container.sh"
RUN_SERVICE_SCRIPT="$REPO_ROOT/.github/actions/scripts/podman/run-service.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"
LOG_FILE="${TMP_DIR}/podman.log"

cat >"${MOCK_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${PODMAN_LOG_FILE:-/tmp/podman.log}"
CMD="$1"
shift || true
case "$CMD" in
  container)
    if [ "${1:-}" = "exists" ]; then
      # signal container missing by exiting 1
      exit 1
    fi
    ;;
  port)
    # Only used when container exists; we already force "exists" to fail
    exit 0
    ;;
  inspect)
    exit 1
    ;;
  stop|rm|pull|login)
    exit 0
    ;;
  run)
    echo "podman run $*" >>"${LOG_FILE}"
    exit 0
    ;;
  *)
    :
    ;;
esac
exit 0
EOF
chmod +x "${MOCK_BIN}/podman"

export PATH="${MOCK_BIN}:${PATH}"
export PODMAN_LOG_FILE="${LOG_FILE}"

# Helper to reset log file between cases
reset_log() {
  : >"${LOG_FILE}"
}

pass_count=0
fail() {
  echo "❌ $1" >&2
  exit 1
}

# Case 1: Traefik mode should not publish host ports
reset_log
ENV_BASE="${TMP_DIR}/env"
mkdir -p "${ENV_BASE}"
HOME="${TMP_DIR}/home" REGISTRY_LOGIN=false IMAGE_NAME="org/app" IMAGE_TAG="latest" \
APP_SLUG="sample" ENV_NAME="production" ENV_FILE_PATH_BASE="${ENV_BASE}" \
TRAEFIK_ENABLED=true DOMAIN_INPUT="example.example" HOST_PORT_IN=9090 \
PODMAN_LOG_FILE="${LOG_FILE}" \
PATH="${PATH}" HOME="${TMP_DIR}/home" \
  bash "${DEPLOY_SCRIPT}" >/dev/null
if grep -q "-p" "${LOG_FILE}"; then
  fail "Traefik deployment unexpectedly published host port"
fi
pass_count=$((pass_count + 1))

# Case 2: Non-numeric host port should fail with error
reset_log
set +e
OUTPUT=$(REGISTRY_LOGIN=false IMAGE_NAME="org/app" IMAGE_TAG="latest" \
  APP_SLUG="sample" ENV_NAME="production" ENV_FILE_PATH_BASE="${ENV_BASE}" \
  TRAEFIK_ENABLED=false HOST_PORT_IN="abc" CONTAINER_PORT_IN=8080 \
  PATH="${PATH}" HOME="${TMP_DIR}/home" \
  bash "${DEPLOY_SCRIPT}" 2>&1)
STATUS=$?
set -e
if [ $STATUS -eq 0 ]; then
  fail "Non-numeric host port succeeded unexpectedly"
fi
if [[ "${OUTPUT}" != *"numeric values"* ]]; then
  fail "Non-numeric host port error message missing context"
fi
pass_count=$((pass_count + 1))

# Case 3: run-service should reject malformed PORTS
set +e
OUTPUT=$(IMAGE="org/app:latest" SERVICE_NAME="example" PORTS="not-a-port" \
  PATH="${PATH}" HOME="${TMP_DIR}/home" \
  bash "${RUN_SERVICE_SCRIPT}" 2>&1)
STATUS=$?
set -e
if [ $STATUS -eq 0 ]; then
  fail "run-service accepted malformed PORTS"
fi
if [[ "${OUTPUT}" != *"Invalid port mapping"* ]]; then
  fail "run-service invalid ports error message missing"
fi
pass_count=$((pass_count + 1))

echo "✅ port argument regression checks passed (${pass_count} cases)"
