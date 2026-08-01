#!/usr/bin/env bash
# package-dmg.sh <path-to-TokenPanel.app> <version>
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <TokenPanel.app> <version>" >&2
  exit 1
fi

APP_PATH="$1"
VERSION="$2"
APP_NAME="TokenPanel"
VOL_NAME="TokenPanel ${VERSION}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokenpanel-dmg.XXXXXX")"
OUT_DIR="${OUT_DIR:-dist}"
DMG_PATH="${OUT_DIR}/${APP_NAME}-${VERSION}.dmg"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGE_DIR/Applications"

# Optional readme on the volume
cat > "$STAGE_DIR/README.txt" <<EOF
TokenPanel ${VERSION}

1. Drag TokenPanel to Applications
2. Launch from Applications (right-click → Open on first launch if needed)
3. Ensure you have run: grok login
EOF

# Remove any previous image
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

echo "Created $DMG_PATH"
ls -lh "$DMG_PATH"
