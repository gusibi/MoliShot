#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="${MOLISHOT_SIGNING_DIR:-$HOME/Library/Application Support/MoliShotSigning}"
cd "$ROOT_DIR"
if [[ ! -f "$SIGNING_DIR/code-signing.p12" ]]; then
  echo "Missing fixed signing identity. See docs/auto-update.md; do not regenerate existing release keys." >&2
  exit 1
fi
# A unique output directory avoids accidentally packaging an old DerivedData app.
OUTPUT_DIR="$(mktemp -d "$ROOT_DIR/dist-update-XXXXXX")"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
xcodegen generate
xcodebuild archive -project MoliShot.xcodeproj -scheme MoliShot \
  -archivePath "$OUTPUT_DIR/MoliShot.xcarchive" -configuration Release CODE_SIGNING_ALLOWED=NO
APP_PATH="$OUTPUT_DIR/MoliShot.xcarchive/Products/Applications/MoliShot.app"
python3 scripts/sign-app.py "$APP_PATH" --signing-dir "$SIGNING_DIR"
./scripts/fetch-sparkle.sh "$OUTPUT_DIR/Sparkle"
python3 scripts/package-update.py "$APP_PATH" --output "$OUTPUT_DIR/release" \
  --sparkle-tools "$OUTPUT_DIR/Sparkle/bin" --key "$SIGNING_DIR/sparkle-private-key.txt"
mkdir -p "$OUTPUT_DIR/dmg"
ditto "$APP_PATH" "$OUTPUT_DIR/dmg/MoliShot.app"
ln -s /Applications "$OUTPUT_DIR/dmg/Applications"
hdiutil create -volname MoliShot -srcfolder "$OUTPUT_DIR/dmg" -ov -format UDZO "$OUTPUT_DIR/release/MoliShot.dmg"
mkdir -p "$ROOT_DIR/dist"
cp "$OUTPUT_DIR/release/"* "$ROOT_DIR/dist/"
echo "Created DMG, update ZIP and signed appcast in $ROOT_DIR/dist"
