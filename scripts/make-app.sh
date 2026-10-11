#!/bin/bash
# Builds MacPorts UI into build/MacPorts UI.app.
#
#   scripts/make-app.sh [debug|release]
#       Ad-hoc signed, no privileged helper: port changes ask for the administrator password.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/make-app.sh release
#       Signed with your certificate (hardened runtime) with the privileged helper embedded.
#       The helper and the app only trust each other when signed by the same team.
#
#   NOTARY_PROFILE=name   Additionally notarizes and staples (profile from `xcrun notarytool store-credentials`).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
IDENTITY="${SIGN_IDENTITY:--}"
APP_ID="com.otstechs.macportsui"
HELPER_ID="$APP_ID.helper"
APP="build/MacPorts UI.app"

echo "==> Building ($CONFIG)"
swift build --package-path MacPortsUI -c "$CONFIG"
BIN="$(swift build --package-path MacPortsUI -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/MacPortsUI" "$APP/Contents/MacOS/MacPortsUI"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleIdentifier</key><string>$APP_ID</string>
	<key>CFBundleName</key><string>MacPorts UI</string>
	<key>CFBundleDisplayName</key><string>MacPorts UI</string>
	<key>CFBundleExecutable</key><string>MacPortsUI</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

OPTIONS=()
if [ "$IDENTITY" != "-" ]; then
	OPTIONS=(--options runtime --timestamp)
	echo "==> Building privileged helper"
	# Universal binary, so the helper matches the app on Intel and Apple Silicon.
	HELPER_OUT="build/helper"
	mkdir -p "$HELPER_OUT"
	for ARCH in x86_64 arm64; do
		swift build --package-path MacPortsKit -c "$CONFIG" --product MacPortsHelper --arch "$ARCH" --scratch-path "build/helper-$ARCH"
	done
	lipo -create "build/helper-x86_64/$CONFIG/MacPortsHelper" "build/helper-arm64/$CONFIG/MacPortsHelper" -output "$HELPER_OUT/$HELPER_ID"
	cp "$HELPER_OUT/$HELPER_ID" "$APP/Contents/MacOS/$HELPER_ID"
	mkdir -p "$APP/Contents/Library/LaunchDaemons"
	cp "Helper/$HELPER_ID.plist" "$APP/Contents/Library/LaunchDaemons/"
	codesign --force "${OPTIONS[@]}" --sign "$IDENTITY" --identifier "$HELPER_ID" "$APP/Contents/MacOS/$HELPER_ID"
fi

echo "==> Signing app with: $IDENTITY"
codesign --force ${OPTIONS[@]+"${OPTIONS[@]}"} --sign "$IDENTITY" --identifier "$APP_ID" "$APP"
codesign --verify --deep --strict "$APP"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$IDENTITY" != "-" ]; then
	echo "==> Notarizing"
	ditto -c -k --keepParent "$APP" build/MacPortsUI.zip
	xcrun notarytool submit build/MacPortsUI.zip --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$APP"
	rm build/MacPortsUI.zip
fi

echo "==> Done: $APP (helper embedded: $([ "$IDENTITY" != "-" ] && echo yes || echo no))"
