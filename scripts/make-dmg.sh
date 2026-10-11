#!/bin/bash
# Packages build/MacPorts UI.app into a signed (and optionally notarized) drag-to-install DMG.
# Usage: SIGN_IDENTITY="Developer ID Application: ..." [NOTARY_PROFILE=macportsui] scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacPorts UI.app"
VOL="MacPorts UI"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/MacPorts-UI-$VERSION.dmg"
RW="build/rw.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "Build the app first: scripts/make-app.sh release" >&2; exit 1; }

echo "==> Rendering background"
rm -rf "$STAGE" "$RW" "$OUT"; mkdir -p "$STAGE/.background"
swift scripts/dmg-background.swift "$STAGE/.background/background.png"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating disk image"
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" -noverify -noautoopen -quiet
sleep 2

echo "==> Laying out the window"
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "MacPorts UI.app" of container window to {165, 215}
    set position of item "Applications" of container window to {495, 215}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
sync
hdiutil detach "/Volumes/$VOL" -quiet

echo "==> Compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -rf "$RW" "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Signing"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT"
    xcrun stapler validate "$OUT"
  fi
fi
echo "==> Done: $OUT"
