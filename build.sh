#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="Autoclicker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift -o /tmp/ac_x86 -target x86_64-apple-macos10.15
swiftc -O main.swift -o /tmp/ac_arm -target arm64-apple-macos11.0
lipo -create /tmp/ac_x86 /tmp/ac_arm -output "$APP/Contents/MacOS/Autoclicker"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Autoclicker</string>
  <key>CFBundleIdentifier</key><string>com.local.autoclicker</string>
  <key>CFBundleExecutable</key><string>Autoclicker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "OK -> $APP"
open "$APP"
