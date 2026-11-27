#!/usr/bin/env bash
# Trigger an EasyPanel Compose deployment for an FCC image tag.
#
# Get the URL: EasyPanel -> your Compose service -> Settings -> Deployment
# Trigger URL (sometimes called "Deploy Hook" or "Webhook URL"). Store the full
# URL as the GitHub secret EASYPANEL_DEPLOY_URL. It is treated as a secret and is
# never printed. The URL and tokens are add-masked when running in Actions.
#
# Usage:
#   EASYPANEL_DEPLOY_URL=... scripts/deploy.sh <image-tag> [--dry-run]
set -euo pipefail

IMAGE_TAG=""
DRY_RUN="${DRY_RUN:-false}"
METHOD="${EASYPANEL_DEPLOY_METHOD:-POST}"
RESPONSE_FILE=""

usage() {
  cat <<'EOF'
Usage: EASYPANEL_DEPLOY_URL=... scripts/deploy.sh <image-tag> [--dry-run]

Deploys the given immutable FCC image tag by calling the EasyPanel Compose
Deployment Trigger URL. Set FCC_IMAGE_TAG in EasyPanel if the service does not
accept runtime tag overrides.
EOF
}

log() {
  printf '[deploy] %s\n' "$*"
}

fail() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "${1:-}" in
    true | True | TRUE | 1 | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [[ -n "${RESPONSE_FILE}" ]]; then
    rm -f "${RESPONSE_FILE}" || true
  fi
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      fail "unknown argument: $1"
      ;;
    *)
      if [[ -n "${IMAGE_TAG}" ]]; then
        fail "only one image tag may be supplied"
      fi
      IMAGE_TAG="$1"
      ;;
  esac
  shift
done

if [[ -z "${IMAGE_TAG}" ]]; then
  usage >&2
  exit 2
fi

if ! [[ "${IMAGE_TAG}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  fail "invalid image tag: ${IMAGE_TAG}"
fi

if [[ -z "${EASYPANEL_DEPLOY_URL:-}" ]]; then
  fail "EASYPANEL_DEPLOY_URL is required"
fi

if ! [[ "${METHOD}" =~ ^[A-Za-z]+$ ]]; then
  fail "invalid EASYPANEL_DEPLOY_METHOD: ${METHOD}"
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  printf '::add-mask::%s\n' "${EASYPANEL_DEPLOY_URL}"
fi

log "FCC image tag: ${IMAGE_TAG}"

if is_true "${DRY_RUN}"; then
  log "DRY RUN: EasyPanel deployment trigger was not called"
  exit 0
fi

PAYLOAD="$(printf '{"image_tag":"%s","FCC_IMAGE_TAG":"%s"}' "${IMAGE_TAG}" "${IMAGE_TAG}")"
RESPONSE_FILE="$(mktemp "${TMPDIR:-/tmp}/fcc-deploy.XXXXXX")"

HTTP_CODE=""
if ! HTTP_CODE="$(curl -s \
  -o "${RESPONSE_FILE}" \
  -w '%{http_code}' \
  --max-time 60 \
  --retry 2 \
  --retry-delay 2 \
  -X "${METHOD}" \
  -H 'Content-Type: application/json' \
  --data "${PAYLOAD}" \
  "${EASYPANEL_DEPLOY_URL}" 2>/dev/null)"; then
  fail "could not contact the EasyPanel deployment endpoint"
fi

if ! [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
  fail "EasyPanel deployment trigger returned HTTP ${HTTP_CODE}"
fi

log "Deployment trigger accepted (HTTP ${HTTP_CODE})"
