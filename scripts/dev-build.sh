#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$HOME/.cargo/env"

echo "==> Building skill-cli"
cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"

echo "==> Verifying skill-cli list"
"$ROOT_DIR/skill-cli/target/debug/skill-cli" list --json \
  | jq '{ok, count: (.data | length)}'

echo "==> Building SwiftUI app"
swift build --package-path "$ROOT_DIR/swift-app"

echo "==> Running Swift tests"
swift test --package-path "$ROOT_DIR/swift-app"

echo "==> Done"
