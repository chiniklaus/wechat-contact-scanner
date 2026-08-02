#!/bin/zsh
# Portable launcher for WeChatContactExporter.swift.
set -u
SCRIPT_DIR="${0:A:h}"
SOURCE="$SCRIPT_DIR/WeChatContactExporter.swift"
CACHE_DIR="$SCRIPT_DIR/.build-cache"
mkdir -p "$CACHE_DIR"
echo "微信联系人导出器"
echo "首次运行时，macOS 会要求“辅助功能”和“屏幕录制”权限。"
echo "所有识别均在本机完成，不会上传联系人数据。"
echo
echo "正在启动（首次编译可能需要约 30 秒）……"
xcrun swift -module-cache-path "$CACHE_DIR" "$SOURCE"
STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  echo
  echo "运行失败，错误码：$STATUS"
  echo "按回车关闭窗口。"
  read
fi
exit $STATUS
