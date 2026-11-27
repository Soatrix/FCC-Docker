#!/usr/bin/env bash
# Roll back Paperclip + FCC by redeploying a previously published immutable tag.
#
# Important: keep previous GHCR version and sha tags immutable; never delete or
# overwrite them. Set FCC_IMAGE_TAG=<tag> in the EasyPanel service environment first, then run this script.
#
# Usage:
#   scripts/rollback.sh sha-abc1234 [--dry-run]
#   EASYPANEL_DEPLOY_URL=... scripts/rollback.sh sha-abc1234
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="${1:-}"

usage() {
  cat <<'EOF'
Usage: scripts/rollback.sh <immutable-tag> [--dry-run]

Examples:
  scripts/rollback.sh 6.19.57
  scripts/rollback.sh sha-abc1234
EOF
}

fail() {
  printf '[rollback] ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "${IMAGE_TAG}" == "-h" || "${IMAGE_TAG}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${IMAGE_TAG}" ]]; then
  usage >&2
  exit 2
fi

REQUESTED_TAG="${IMAGE_TAG}"
if [[ "${IMAGE_TAG}" == */*:* ]]; then
  IMAGE_TAG="${IMAGE_TAG##*:}"
fi

if ! [[ "${IMAGE_TAG}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  fail "invalid image tag: ${REQUESTED_TAG}"
fi

shift
printf '[rollback] Ensure EasyPanel FCC_IMAGE_TAG is set to %s before triggering redeploy\n' "${IMAGE_TAG}"
exec bash "${SCRIPT_DIR}/deploy.sh" "${IMAGE_TAG}" "$@"
