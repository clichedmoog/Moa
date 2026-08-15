#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SandboxProbe
BIN=$(swift build -c release --product SandboxProbe --show-bin-path)/SandboxProbe

APP=".build/SandboxProbe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SandboxProbe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SandboxProbe</string>
	<key>CFBundleIdentifier</key><string>com.clichedmoog.SandboxProbe</string>
	<key>CFBundleName</key><string>SandboxProbe</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

codesign --force --sign - \
    --entitlements Scripts/SandboxProbe.entitlements \
    --options runtime "$APP"

echo "빌드 완료: $APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -
