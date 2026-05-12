#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-$ROOT_DIR/skill-cli/target/debug/skill-cli}"
TMP_DIR="$(mktemp -d)"

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

missing_stderr="$TMP_DIR/missing-detail.err"
if "$CLI" detail "__popskill_missing_skill__" --json > /dev/null 2> "$missing_stderr"; then
  echo "expected missing detail command to fail" >&2
  exit 1
fi
jq -e '.ok == false and (.error.message | length > 0)' "$missing_stderr" > /dev/null
echo "error-envelope ok"
