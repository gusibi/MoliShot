#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MoliShot"
SCHEME="MoliShot"
CONFIGURATION="Release"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

echo "==> Generating Xcode project"
cd "$ROOT_DIR"
xcodegen generate

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$ROOT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  build

echo "==> Locating built app"
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/$CONFIGURATION/$APP_NAME.app" -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "Failed to locate $APP_NAME.app in DerivedData" >&2
  exit 1
fi

echo "==> Preparing dist folder"
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG at $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE_DIR"

echo "==> Done"
echo "$DMG_PATH"

open "$DIST_DIR"
