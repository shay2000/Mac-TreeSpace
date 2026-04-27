#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TreeSpace"
BUILD_DIR="$PROJECT_DIR/builds"
SPM_BUILD="$BUILD_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RESOURCES_SRC="$PROJECT_DIR/Sources/TreeSpace/Resources"

echo "Building $APP_NAME..."
swift build -c release --build-path "$SPM_BUILD"

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$SPM_BUILD/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TreeSpace</string>
    <key>CFBundleDisplayName</key>
    <string>TreeSpace</string>
    <key>CFBundleIdentifier</key>
    <string>com.shayprasad.treespace</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>TreeSpace</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Icon: build .icns from existing PNGs
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
cp "$RESOURCES_SRC/AppIcon-16.png"  "$ICONSET/icon_16x16.png"
cp "$RESOURCES_SRC/AppIcon-32.png"  "$ICONSET/icon_16x16@2x.png"
cp "$RESOURCES_SRC/AppIcon-32.png"  "$ICONSET/icon_32x32.png"
cp "$RESOURCES_SRC/AppIcon-64.png"  "$ICONSET/icon_32x32@2x.png"
cp "$RESOURCES_SRC/AppIcon-128.png" "$ICONSET/icon_128x128.png"
cp "$RESOURCES_SRC/AppIcon-256.png" "$ICONSET/icon_128x128@2x.png"
cp "$RESOURCES_SRC/AppIcon-256.png" "$ICONSET/icon_256x256.png"
cp "$RESOURCES_SRC/AppIcon-512.png" "$ICONSET/icon_256x256@2x.png"
cp "$RESOURCES_SRC/AppIcon-512.png" "$ICONSET/icon_512x512.png"
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Done → $APP_BUNDLE"
