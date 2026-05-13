#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_MUTATING=false

for arg in "$@"; do
  case "$arg" in
    --mutating)
      RUN_MUTATING=true
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: scripts/ci-local.sh [--mutating]

Runs the local verification suite:
  - Rust sidecar build and read-only smoke
  - SwiftUI app build
  - Swift tests
  - native launch smoke
  - .app bundle launch smoke
  - screenshot asset smoke
  - release artifact smoke

Pass --mutating to also run sidecar smoke tests that create and remove
a temporary CC Switch skill repository.
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "usage: scripts/ci-local.sh [--mutating]" >&2
      exit 64
      ;;
  esac
done

echo "==> Local CI: shell script syntax"
for script in "$ROOT_DIR"/scripts/*.sh; do
  bash -n "$script"
done

echo "==> Local CI: build, read-only smoke, and tests"
"$ROOT_DIR/scripts/dev-build.sh"

echo "==> Local CI: native app launch smoke"
"$ROOT_DIR/scripts/smoke-app.sh" 2

echo "==> Local CI: bundled app launch smoke"
"$ROOT_DIR/scripts/smoke-bundle.sh" 2

echo "==> Local CI: screenshot asset smoke"
"$ROOT_DIR/scripts/smoke-screenshots.sh"

echo "==> Local CI: release artifact smoke"
"$ROOT_DIR/scripts/smoke-release.sh"

if [[ "$RUN_MUTATING" == true ]]; then
  echo "==> Local CI: mutating sidecar smoke"
  "$ROOT_DIR/scripts/smoke-cli-mutating.sh"
else
  echo "==> Local CI: skipped mutating smoke (pass --mutating to run it)"
fi

echo "==> Local CI: ok"
