#!/usr/bin/env bash
# Check upstream free-claude-code releases and update config/fcc-version.json.
# This script never builds, publishes, or deploys anything.
set -euo pipefail

REPO="${UPSTREAM_REPO:-Alishahryar1/free-claude-code}"
CONFIG_FILE="${CONFIG_FILE:-config/fcc-version.json}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
LATEST_RELEASE_API="https://api.github.com/repos/${REPO}/releases/latest"
LATEST_TAG_API="https://api.github.com/repos/${REPO}/tags?per_page=1"
TMP_DIR=""

log() {
  printf '[upstream] %s\n' "$*"
}

fail() {
  printf '[upstream] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
[[ -f "${CONFIG_FILE}" ]] || fail "missing ${CONFIG_FILE}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fcc-upstream.XXXXXX")"
RAW_JSON="${TMP_DIR}/upstream.json"
PARSED_TSV="${TMP_DIR}/parsed.tsv"
NOTES_FILE="${RELEASE_NOTES_FILE:-${TMP_DIR}/release-notes.md}"

CURL_ARGS=(-fsSL -H 'Accept: application/vnd.github+json')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::add-mask::%s\n' "${GITHUB_TOKEN}"
  fi
  CURL_ARGS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

if ! curl "${CURL_ARGS[@]}" -o "${RAW_JSON}" "${LATEST_RELEASE_API}" 2>/dev/null; then
  log "No release found; checking latest tag instead"
  if ! curl "${CURL_ARGS[@]}" -o "${RAW_JSON}" "${LATEST_TAG_API}" 2>/dev/null; then
    fail "unable to query GitHub API for ${REPO}"
  fi
fi

if ! python3 - "${RAW_JSON}" "${PARSED_TSV}" "${NOTES_FILE}" "${REPO}" <<'PY'
import json
import re
import sys

raw_path, parsed_path, notes_path, repo = sys.argv[1:5]

with open(raw_path, encoding="utf-8") as handle:
    data = json.load(handle)

if isinstance(data, list):
    if not data:
        raise SystemExit("no upstream tags returned")
    item = data[0]
    tag = item.get("name", "")
    url = item.get("commit", {}).get("url", "")
    published = ""
    notes = "Latest upstream tag: {}\n".format(tag)
elif isinstance(data, dict):
    tag = data.get("tag_name") or data.get("name") or ""
    url = data.get("html_url", "")
    published = data.get("published_at") or data.get("created_at") or ""
    notes = data.get("body") or "No release notes were published upstream."
else:
    raise SystemExit("unexpected GitHub API response")

if not tag:
    raise SystemExit("upstream response did not include a tag")

version = re.sub(r"^(?:fcc[-_]?)?[vV]", "", tag).strip()
if not version:
    raise SystemExit("could not derive a version from tag: {}".format(tag))

with open(parsed_path, "w", encoding="utf-8") as handle:
    handle.write("\t".join([version, tag, url, published]) + "\n")

body = (
    "Upstream FCC release detected: **{}**\n\n"
    "Tag: `{}`  \n"
    "Repository: https://github.com/{}\n"
).format(version, tag, repo)
if published:
    body += "Published: `{}`\n\n".format(published)
if url:
    body += "Reference: {}\n\n".format(url)
body += "## Upstream release notes\n\n"
body += notes[:10000]
body += (
    "\n\n---\n\n"
    "Review this PR, then run the **Build and publish FCC** workflow. "
    "Do not auto-merge."
)
with open(notes_path, "w", encoding="utf-8") as handle:
    handle.write(body)
PY
then
  fail "could not parse upstream release response"
fi

IFS=$'\t' read -r LATEST_VERSION LATEST_TAG LATEST_URL PUBLISHED_AT < "${PARSED_TSV}"

if [[ -z "${LATEST_VERSION}" ]]; then
  fail "derived an empty upstream version"
fi

CURRENT_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "${CONFIG_FILE}")"

UPDATE_NEEDED=false
if [[ "${LATEST_VERSION}" == "${CURRENT_VERSION}" ]]; then
  log "No update needed: ${CONFIG_FILE} is already at ${CURRENT_VERSION}"
else
  log "Update needed: configured=${CURRENT_VERSION} upstream=${LATEST_VERSION}"
  python3 - "${CONFIG_FILE}" "${LATEST_VERSION}" <<'PY'
import json
import sys

path, version = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    config = json.load(handle)
config["version"] = version
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
PY
  UPDATE_NEEDED=true
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'update_needed=%s\n' "${UPDATE_NEEDED}"
    printf 'current_version=%s\n' "${CURRENT_VERSION}"
    printf 'latest_version=%s\n' "${LATEST_VERSION}"
  } >> "${GITHUB_OUTPUT}"
fi

printf 'UPDATE_NEEDED=%s\n' "${UPDATE_NEEDED}"
printf 'CURRENT_VERSION=%s\n' "${CURRENT_VERSION}"
printf 'LATEST_VERSION=%s\n' "${LATEST_VERSION}"
