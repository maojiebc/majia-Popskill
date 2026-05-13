#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Popskill.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"
swift build --package-path "$ROOT_DIR/swift-app"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$ROOT_DIR/swift-app/.build/debug/Popskill" "$MACOS_DIR/Popskill"
cp "$ROOT_DIR/skill-cli/target/debug/skill-cli" "$RESOURCES_DIR/skill-cli"
cp "$ROOT_DIR/docs/ipc.md" "$RESOURCES_DIR/ipc.md"
chmod +x "$MACOS_DIR/Popskill" "$RESOURCES_DIR/skill-cli"

SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/swift-app/.build/artifacts" -path "*/Sparkle.framework" -type d 2>/dev/null | sort | head -n 1 || true)"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
fi

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

if [[ -n "${POPSKILL_SPARKLE_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${POPSKILL_SPARKLE_FEED_URL}" "$CONTENTS_DIR/Info.plist"
fi

if [[ -n "${POPSKILL_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${POPSKILL_SPARKLE_PUBLIC_ED_KEY}" "$CONTENTS_DIR/Info.plist"
fi

echo "$APP_DIR"
