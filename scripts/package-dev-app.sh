#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Popskill.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

source "$HOME/.cargo/env"

cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"
swift build --package-path "$ROOT_DIR/swift-app"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/swift-app/.build/debug/Popskill" "$MACOS_DIR/Popskill"
cp "$ROOT_DIR/skill-cli/target/debug/skill-cli" "$RESOURCES_DIR/skill-cli"
chmod +x "$MACOS_DIR/Popskill" "$RESOURCES_DIR/skill-cli"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Popskill</string>
  <key>CFBundleIdentifier</key>
  <string>com.maojiebc.popskill.dev</string>
  <key>CFBundleName</key>
  <string>Popskill</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0-dev</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
