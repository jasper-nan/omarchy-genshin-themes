#!/usr/bin/env bash
# 安装主题到 Omarchy 用户主题目录
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/.config/omarchy/themes"
mkdir -p "$DEST"
count=0
for t in "$DIR"/themes/*/; do
  name=$(basename "$t")
  cp -r "$t" "$DEST/$name"
  echo "安装 $name"
  count=$((count+1))
done
echo "完成: $count 个主题 → $DEST"
echo "运行 omarchy theme list 查看, omarchy theme set \"<名称>\" 应用"
