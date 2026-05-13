#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-$ROOT_DIR/skill-cli/target/debug/skill-cli}"
TMP_DIR="$(mktemp -d)"
OWNER="popskill-smoke-temp"
NAME="repo-$(date +%s)"

if ! command -v jq > /dev/null; then
  echo "jq is required for mutating skill-cli smoke tests. Install it with: brew install jq" >&2
  exit 127
fi

cleanup() {
  "$CLI" repo-remove --owner "$OWNER" --name "$NAME" --json > /dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Smoke testing mutating skill-cli repo commands"

invalid_output="$TMP_DIR/invalid-repo-add.err"
if "$CLI" repo-add \
  --owner " " \
  --name "$NAME" \
  --branch main \
  --enabled false \
  --json \
  > /dev/null \
  2> "$invalid_output"; then
  echo "expected blank repository owner to fail" >&2
  exit 1
fi
jq -e '.ok == false and (.error.message | contains("repository owner is required"))' \
  "$invalid_output" > /dev/null
echo "repo-add validation ok"

"$CLI" repo-add \
  --owner "$OWNER" \
  --name "$NAME" \
  --branch main \
  --enabled false \
  --json \
  | jq -e --arg owner "$OWNER" --arg name "$NAME" \
      '.ok == true and .data.owner == $owner and .data.name == $name and .data.enabled == false' \
      > /dev/null
echo "repo-add ok"

"$CLI" repo-toggle \
  --owner "$OWNER" \
  --name "$NAME" \
  --enabled true \
  --json \
  | jq -e --arg owner "$OWNER" --arg name "$NAME" \
      '.ok == true and .data.owner == $owner and .data.name == $name and .data.enabled == true' \
      > /dev/null
echo "repo-toggle ok"

"$CLI" repo-remove \
  --owner "$OWNER" \
  --name "$NAME" \
  --json \
  | jq -e '.ok == true' > /dev/null

trap - EXIT
if "$CLI" repo-list --json | jq -e --arg owner "$OWNER" --arg name "$NAME" \
  '.data[] | select(.owner == $owner and .name == $name)' > /dev/null; then
  echo "temporary repository was not removed" >&2
  exit 1
fi
echo "repo-remove ok"
