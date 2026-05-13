#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_PATH="${1:-${POPSKILL_DMG_PATH:-$ROOT_DIR/build/Popskill.dmg}}"
PRIVATE_KEY_FILE="${POPSKILL_SPARKLE_ED_PRIVATE_KEY_FILE:-}"
PRIVATE_KEY="${POPSKILL_SPARKLE_ED_PRIVATE_KEY:-}"

die() {
  echo "sparkle-sign-update: $*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: scripts/sparkle-sign-update.sh [artifact-path]

Signs a Sparkle update artifact and prints the generated appcast attributes.
Defaults to build/Popskill.dmg or POPSKILL_DMG_PATH.

Private key sources:
  POPSKILL_SPARKLE_ED_PRIVATE_KEY_FILE  path to an exported EdDSA private key
  POPSKILL_SPARKLE_ED_PRIVATE_KEY       private key value passed on stdin
  Keychain                              Sparkle default when neither env is set
USAGE
  exit 0
fi

[[ -f "$ARTIFACT_PATH" ]] || die "artifact not found: $ARTIFACT_PATH"

SIGN_UPDATE="$("$ROOT_DIR/scripts/sparkle-tool.sh" sign_update)"
signature_output=""

if [[ -n "$PRIVATE_KEY_FILE" ]]; then
  [[ -f "$PRIVATE_KEY_FILE" ]] || die "private key file not found: $PRIVATE_KEY_FILE"
  signature_output="$("$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY_FILE" "$ARTIFACT_PATH")"
elif [[ -n "$PRIVATE_KEY" ]]; then
  signature_output="$(printf '%s' "$PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ARTIFACT_PATH")"
else
  signature_output="$("$SIGN_UPDATE" "$ARTIFACT_PATH")"
fi

printf '%s\n' "$signature_output"

ed_signature="$(printf '%s\n' "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"
if [[ -n "$ed_signature" ]]; then
  printf '\nexport POPSKILL_SPARKLE_ED_SIGNATURE=%q\n' "$ed_signature"
fi
