#!/bin/bash
# 打包 StockBar 成可散佈的 .app bundle（穩定 self-signed 簽章、未公證）
# 用法：Scripts/build-app.sh [version]   例：Scripts/build-app.sh 1.0.0
#
# 簽章身分：SIGN_IDENTITY（預設 "StockBar Self-Signed"）
#   用固定憑證簽章，讓每次重 build 的 designated requirement 都一致
#   （identifier + certificate leaf），macOS Tahoe 才會當成同一個 app、
#   「允許在選單列」開關才不會每次重 build 又跑出新項目、又被關掉。
#   憑證不存在時自動退回 ad-hoc（並警告）。
set -euo pipefail

VERSION="${1:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-StockBar Self-Signed}"
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 放入 app icon"
mkdir -p "$APP/Contents/Resources"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "   (略過：找不到 Resources/AppIcon.icns)"
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "==> 穩定簽章：$SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> 警告：找不到憑證 '$SIGN_IDENTITY'，退回 ad-hoc（重 build 會在 Tahoe 產生新的選單列項目）"
    codesign --force --deep --sign - "$APP"
fi

echo "==> 壓 zip"
mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/StockBar-$VERSION.zip"
rm -f "$ZIP"
# ditto 保留 bundle 結構與簽章
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 完成：$ZIP"
