#!/bin/bash
# 一键打包:swift build → DoriCall.app → DoriCall.zip
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ swift build -c release (universal: arm64 + x86_64)"
# 通用二进制:团队里有 Intel Mac 也能跑;带 --arch 时产物在 .build/apple/ 下,路径用 --show-bin-path 拿
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DoriCall"

APP="build/DoriCall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DoriCall"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/menubar.png "$APP/Contents/Resources/menubar.png"
cp Assets/dori-*.png "$APP/Contents/Resources/"   # 卡片上的 Dori 表情贴纸

# ad-hoc 签名(团队内部分发够用;同事首次打开按安装说明放行)
codesign --force -s - "$APP"

(cd build && rm -f DoriCall.zip && ditto -c -k --keepParent DoriCall.app DoriCall.zip)
echo "✅ 产出: build/DoriCall.app 和 build/DoriCall.zip"
