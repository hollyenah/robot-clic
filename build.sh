#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="Robot-clic.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling Intel (macOS 10.15+)…"
swiftc -O main.swift -o /tmp/robotclic_x86 -target x86_64-apple-macos10.15

echo "Compiling Apple Silicon (macOS 11+)…"
swiftc -O main.swift -o /tmp/robotclic_arm -target arm64-apple-macos11.0.2

lipo -create /tmp/robotclic_x86 /tmp/robotclic_arm -output "$APP/Contents/MacOS/Robot-clic"
rm -f /tmp/robotclic_x86 /tmp/robotclic_arm

# Icon (needs icon.png, 1024x1024, in this folder)
ICONSET="/tmp/robotclic.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0.2" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0.2//EN" "http://www.apple.com/DTDs/PropertyList-1.0.2.dtd">
<plist version="1.0.2">
<dict>
  <key>CFBundleName</key><string>Robot-clic</string>
  <key>CFBundleIdentifier</key><string>com.local.robotclic</string>
  <key>CFBundleExecutable</key><string>Robot-clic</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0.2</string>
  <key>CFBundleShortVersionString</key><string>1.0.2</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "OK -> $APP"
open "$APP"