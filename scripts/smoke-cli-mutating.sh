#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-$ROOT_DIR/skill-cli/target/debug/skill-cli}"
OWNER="popskill-smoke-temp"
NAME="repo-$(date +%s)"

cleanup() {
  "$CLI" repo-remove --owner "$OWNER" --name "$NAME" --json > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Smoke testing mutating skill-cli repo commands"

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
