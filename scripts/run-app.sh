#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"
swift build --package-path "$ROOT_DIR/swift-app"

export POPSKILL_CLI="$ROOT_DIR/skill-cli/target/debug/skill-cli"
exec "$ROOT_DIR/swift-app/.build/debug/Popskill"
