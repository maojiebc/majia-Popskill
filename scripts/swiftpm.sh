#!/usr/bin/env bash
set -euo pipefail

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/popskill-swiftpm-home.XXXXXX")"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

HOME="$TMP_HOME" \
GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_NOSYSTEM=1 \
GIT_TERMINAL_PROMPT=0 \
swift "$@"
