#!/bin/bash
# 打包 StockBar 成可散佈的 .app bundle（ad-hoc 簽章、未公證）
# 用法：Scripts/build-app.sh [version]   例：Scripts/build-app.sh 1.0.0
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/StockBar.app"
BIN_NAME="StockBar"

echo "==> swift build (release)"
cd "$ROOT"
swift build -c release

echo "==> 組 .app bundle (v$VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>StockBar</string>
    <key>CFBundleDisplayName</key><string>StockBar</string>
    <key>CFBundleIdentifier</key><string>com.oscar3x39.stockbar</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 簽章"
codesign --force --deep --sign - "$APP"

echo "==> 壓 zip"
mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/StockBar-$VERSION.zip"
rm -f "$ZIP"
# ditto 保留 bundle 結構與簽章
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 完成：$ZIP"
