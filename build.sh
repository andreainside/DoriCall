#!/bin/bash
# 一键打包:swift build → DoriCall.app → DoriCall.zip
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ swift build -c release"
swift build -c release

APP="build/DoriCall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DoriCall "$APP/Contents/MacOS/DoriCall"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/menubar.png "$APP/Contents/Resources/menubar.png"

# ad-hoc 签名(团队内部分发够用;同事首次打开按安装说明放行)
codesign --force -s - "$APP"

(cd build && rm -f DoriCall.zip && ditto -c -k --keepParent DoriCall.app DoriCall.zip)
echo "✅ 产出: build/DoriCall.app 和 build/DoriCall.zip"
