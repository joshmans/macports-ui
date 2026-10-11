#!/bin/sh
# Builds MacPorts UI and wraps it in an ad-hoc signed .app bundle at build/MacPorts UI.app.
# Usage: scripts/make-app.sh [debug|release]
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build --package-path MacPortsUI -c "$CONFIG"
BIN="$(swift build --package-path MacPortsUI -c "$CONFIG" --show-bin-path)/MacPortsUI"
APP="build/MacPorts UI.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MacPortsUI"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleIdentifier</key><string>com.otstechs.macportsui</string>
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
codesign --force --sign - "$APP"
echo "Built $APP"
