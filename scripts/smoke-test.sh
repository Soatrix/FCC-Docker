#!/usr/bin/env bash
# Smoke-test a locally built FCC image without publishing a host port.
# Usage: FCC_VERSION_EXPECTED=6.19.57 scripts/smoke-test.sh <image:tag>
set -euo pipefail

IMAGE="${1:-}"
EXPECTED_VERSION="${FCC_VERSION_EXPECTED:-}"
DEFAULT_MODEL="nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b"
MODELS_URL='http://127.0.0.1:8082/v1/models?view=messages'
CONTAINER=""
TOKEN=0123456789abcdef0123456789abcdef
AUTH_ARGS=()
if [[ "${FCC_SMOKE_AUTH:-true}" == "true" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${TOKEN}")
else
  TOKEN=""
fi

log() {
  printf '[smoke] %s\n' "$*"
}

fail() {
  printf '[smoke] FAIL: %s\n' "$*" >&2
  if [[ -n "${CONTAINER}" ]]; then
    docker logs --tail 100 "${CONTAINER}" >&2 || true
  fi
  exit 1
}

cleanup() {
  if [[ -n "${CONTAINER}" ]]; then
    docker rm -fv "${CONTAINER}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "${IMAGE}" ]]; then
  printf 'Usage: %s <image:tag>\n' "$0" >&2
  exit 2
fi

command -v docker >/dev/null 2>&1 || fail "docker is required"

MODEL_TO_TEST="${DEFAULT_MODEL}"
MODEL_WAS_OVERRIDDEN=0
if [[ -n "${MODEL:-}" ]]; then
  MODEL_TO_TEST="${MODEL}"
  MODEL_WAS_OVERRIDDEN=1
fi

CONTAINER="fcc-smoke-$(date +%s)-$$"
log "Starting ${IMAGE} as ${CONTAINER} (no published ports)"
docker run -d --name "${CONTAINER}" \
  -e HOST=0.0.0.0 \
  -e PORT=8082 \
  -e FCC_OPEN_BROWSER=false \
  -e FCC_PROXY_TOKEN="${TOKEN}" \
  -v /root/.fcc \
  -e NVIDIA_NIM_API_KEY=smoke-test-placeholder \
  -e MODEL="${MODEL_TO_TEST}" \
  "${IMAGE}" >/dev/null || fail "container failed to start"

log "Waiting for http://127.0.0.1:8082/health"
healthy=0
for ((attempt = 0; attempt < 60; attempt++)); do
  if ! docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -qx true; then
    break
  fi
  if docker exec "${CONTAINER}" curl -fsS http://127.0.0.1:8082/health >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 2
done
if [[ "${healthy}" -ne 1 ]]; then
  fail "FCC did not become healthy within 120 seconds"
fi

if [[ -n "${EXPECTED_VERSION}" ]]; then
  log "Checking fcc-server --version == ${EXPECTED_VERSION}"
  version_output="$(docker exec "${CONTAINER}" fcc-server --version 2>&1)" \
    || fail "fcc-server --version failed"
  if ! printf '%s\n' "${version_output}" | grep -Fq -- "${EXPECTED_VERSION}"; then
    fail "expected FCC version ${EXPECTED_VERSION}, got: $(printf '%s\n' "${version_output}" | tr '\n' ' ')"
  fi
else
  log "FCC_VERSION_EXPECTED not set; skipping version assertion"
fi

unauth_status="$(docker exec "${CONTAINER}" curl -s -o /dev/null -w '%{http_code}' "${MODELS_URL}")"
if [[ -n "${TOKEN}" ]]; then
  case "${unauth_status}" in 401|403) ;; *) fail "unauthenticated model request returned ${unauth_status}" ;; esac
else
  [[ "${unauth_status}" == 200 ]] || fail "unauthenticated mode returned ${unauth_status}"
fi

models_json="$(docker exec "${CONTAINER}" curl -fsS "${AUTH_ARGS[@]}" "${MODELS_URL}")" \
  || fail "models endpoint did not return a response"

if ! printf '%s' "${models_json}" \
  | docker exec -i "${CONTAINER}" python3 -c 'import json, sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  fail "models endpoint did not return valid JSON"
fi

if [[ "${MODEL_WAS_OVERRIDDEN}" -eq 0 ]]; then
  log "Checking default_model_id == ${DEFAULT_MODEL}"
  if ! printf '%s\n' "${models_json}" \
    | grep -Eq "\"default_model_id\"[[:space:]]*:[[:space:]]*\"${DEFAULT_MODEL}\""; then
    fail "models JSON does not contain default_model_id=${DEFAULT_MODEL}"
  fi
else
  log "MODEL override detected; skipping default_model_id assertion"
fi

if [[ -n "${TOKEN}" ]]; then
  log "Restarting to verify persisted configuration"
  docker restart "${CONTAINER}" >/dev/null
  ready=0
  for ((attempt = 0; attempt < 60; attempt++)); do
    if docker exec "${CONTAINER}" curl -fsS "${AUTH_ARGS[@]}" "${MODELS_URL}" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  [[ "${ready}" == 1 ]] || fail "Authenticated proxy did not recover after restart"
fi

log "PASS: ${IMAGE}"
