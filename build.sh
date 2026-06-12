#!/bin/zsh
# Build Chime.app from Chime.swift (no Xcode project needed)
set -e
cd "$(dirname "$0")"

APP="Chime.app"
swiftc -O -swift-version 5 Chime.swift -o Chime

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv Chime "$APP/Contents/MacOS/Chime"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.partyfly.chime</string>
  <key>CFBundleName</key><string>Chime</string>
  <key>CFBundleDisplayName</key><string>Chime</string>
  <key>CFBundleExecutable</key><string>Chime</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ad-hoc sign so notifications & TCC behave
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# make the agent CLI executable
chmod +x chime 2>/dev/null || true

echo "Built: $PWD/$APP"
echo "Run:   open \"$PWD/$APP\""
echo "CLI:   ./chime status   (symlink onto PATH to use anywhere)"
