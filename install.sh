#!/bin/bash
# 重新 build 并更新 /Applications 里的 Bento。
# 改完代码跑这个就行：./install.sh
set -e

cd "$(dirname "$0")"
APP=/Applications/Bento.app

echo "▸ 编译 Release…"
xcodebuild -project Bento.xcodeproj -scheme Bento -configuration Release build \
  > /tmp/bento-build.log 2>&1 || {
    echo "✗ 编译失败，最后 20 行："
    tail -20 /tmp/bento-build.log
    exit 1
  }

BUILT=$(ls -d ~/Library/Developer/Xcode/DerivedData/Bento-*/Build/Products/Release/Bento.app | head -1)
echo "▸ 产物 $(du -sh "$BUILT" | cut -f1)"

echo "▸ 退出运行中的实例…"
pkill -f "Bento.app/Contents/MacOS/Bento" 2>/dev/null || true
sleep 1

echo "▸ 安装到 $APP …"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
codesign -v "$APP" && echo "  签名有效"

echo "▸ 重新注册 LaunchServices（Services 菜单靠它定位 App）…"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSREG" -f "$APP"

echo "▸ 启动…"
open "$APP"

echo
echo "✓ 完成。"
echo
echo "  CLI 伴生（可选，需要管理员权限，只用装一次）："
echo "  sudo mkdir -p /usr/local/bin && \\"
echo "    printf '#!/bin/sh\\\\nexec \"$APP/Contents/MacOS/Bento\" \"\$@\"\\\\n' | \\"
echo "    sudo tee /usr/local/bin/bento >/dev/null && sudo chmod +x /usr/local/bin/bento"
echo
echo "  装好后：echo '{\"a\":1}' | bento json"
