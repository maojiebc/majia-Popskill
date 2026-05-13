#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-$ROOT_DIR/skill-cli/target/debug/skill-cli}"
TMP_DIR="$(mktemp -d)"

if ! command -v jq > /dev/null; then
  echo "jq is required for skill-cli smoke tests. Install it with: brew install jq" >&2
  exit 127
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_ok() {
  local name="$1"
  shift
  local output="$TMP_DIR/$name.json"

  "$CLI" "$@" > "$output"
  jq -e '.ok == true' "$output" > /dev/null

  printf "%s " "$name"
  jq -c '{ok, count: (if (.data | type) == "array" then (.data | length) else null end)}' "$output"
}

echo "==> Smoke testing skill-cli"

list_output="$TMP_DIR/list.json"
"$CLI" list --json > "$list_output"
jq -e '.ok == true and (.data | type) == "array"' "$list_output" > /dev/null
printf "list "
jq -c '{ok, count: (.data | length)}' "$list_output"

first_skill_id="$(jq -r '.data[0].id // empty' "$list_output")"
if [[ -n "$first_skill_id" ]]; then
  detail_output="$TMP_DIR/detail.json"
  "$CLI" detail "$first_skill_id" --json > "$detail_output"
  jq -e --arg id "$first_skill_id" '.ok == true and .data.id == $id' "$detail_output" > /dev/null
  echo "detail ok"
else
  echo "detail skipped: no installed skills"
fi

require_ok scan-unmanaged scan-unmanaged --json
require_ok backup-list backup-list --json
require_ok stub-list stub-list --json
require_ok repo-list repo-list --json
require_ok webdav-status webdav-status --json
require_ok security-scan-list security-scan-list --json

scan_dir="$TMP_DIR/security-scan-skill"
mkdir -p "$scan_dir"
printf '# Smoke Skill\n' > "$scan_dir/SKILL.md"
security_output="$TMP_DIR/security-scan.json"
POPSKILL_AGENTSHIELD_BIN=/bin/echo "$CLI" security-scan "$scan_dir" --json > "$security_output"
jq -e '.ok == true and .data.scanner == "ecc-agentshield" and .data.status == "verified"' "$security_output" > /dev/null
echo "security-scan ok"

health_output="$TMP_DIR/health.json"
"$CLI" health --json > "$health_output"
jq -e '.ok == true and (.data.installedCount | type) == "number"' "$health_output" > /dev/null
printf "health "
jq -c '{ok, installed: .data.installedCount, unmanaged: .data.unmanagedCount, backups: .data.backupCount, repositories: .data.repositoryCount, enabledRepositories: .data.enabledRepositoryCount, version: .data.sidecarVersion}' "$health_output"

missing_stderr="$TMP_DIR/missing-detail.err"
if "$CLI" detail "__popskill_missing_skill__" --json > /dev/null 2> "$missing_stderr"; then
  echo "expected missing detail command to fail" >&2
  exit 1
fi
jq -e '.ok == false and (.error.message | length > 0)' "$missing_stderr" > /dev/null
echo "error-envelope ok"
