#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

echo "==> Building skill-cli"
cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"

echo "==> Running skill-cli tests"
cargo test --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"

"$ROOT_DIR/scripts/smoke-cli.sh" "$ROOT_DIR/skill-cli/target/debug/skill-cli"

echo "==> Building SwiftUI app"
"$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app"

echo "==> Running Swift tests"
"$ROOT_DIR/scripts/swiftpm.sh" test --package-path "$ROOT_DIR/swift-app"

echo "==> Done"
