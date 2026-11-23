#!/bin/bash
# Build dist/通不连.app on macOS. This script does not change network settings.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "通不连的 .app 只能在 macOS 上打包。当前系统是 $(uname -s)。" >&2
  echo "诊断核心在这台机器上可以用：swift test" >&2
  echo "干跑示例：swift run tongbulian diagnose --demo leftover" >&2
  exit 2
fi

swift build -c release --product TongbulianApp
APP="dist/通不连.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/TongbulianApp" "$APP/Contents/MacOS/Tongbulian"
cp "packaging/Info.plist" "$APP/Contents/Info.plist"

# Info.plist CFBundleIconFile = AppIcon → Contents/Resources/AppIcon.icns
ICON_SRC="packaging/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign only after the icon is inside the bundle.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi
echo "已生成 $APP"
echo "首次打开：在 Finder 里右键「通不连」，选择「打开」。若被拦截，到系统设置 → 隐私与安全性 → 仍要打开。"
echo "这个包是本机临时签名，不是 Apple 公证过的。"
