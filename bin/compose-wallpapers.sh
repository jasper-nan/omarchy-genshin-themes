#!/usr/bin/env bash
# 合成 4K 主题壁纸
# 用法: compose-wallpapers.sh <theme-dir> <slug> <mode: direct|compose>
#   direct  : 已有 4K 横屏原图 (src/wallpaper.img), 只加可读性暗带
#   compose : 官方立绘 (src/art.png) + 主题渐变底 + 羽化融入 + 暗带
# 读取 <theme-dir>/colors.toml 的配色
set -euo pipefail

DIR=$1; SLUG=$2; KIND=$3
W=3840; H=2160
CT="$DIR/colors.toml"
OUT="$DIR/backgrounds"

c() { grep -E "^$1 *= *" "$CT" | head -1 | sed -E 's/.*= *"([^"]+)".*/\1/'; }

MODE=$(grep -E '^mode *=' "$CT" | sed -E 's/.*"([^"]+)".*/\1/')
BG=$(c background); DBG=$(c dark_background); ACC=$(c accent); FG=$(c foreground)

# 暗带颜色: 深色主题用更深的底色, 浅色主题用主题底色
if [[ $MODE == light ]]; then BAND=$BG; else BAND=$DBG; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 立绘目标高度: 画布 88%, 但限制放大倍率 (大图≤1.35x, 小图≤1.6x)
art_target_h() {
  local ah aw cap; read -r aw ah < <(identify -format '%w %h\n' "$1" || true)
  cap=1.35; (( aw < 1500 )) && cap=1.6
  python3 -c "print(min(int($H*0.88), int($ah*$cap)))"
}

# 边缘羽化蒙版: 外沿大面积柔和渐隐 (与模糊底自然融合)
feather() { # $1=in $2=out [$3=羽化px]
  local fw=${3:-180} aw ah
  read -r aw ah < <(identify -format '%w %h\n' "$1" || true)
  magick -size ${aw}x${ah} xc:white -shave ${fw}x${fw} \
    -bordercolor black -border ${fw} -blur 0x$((fw*3/4)) -level 8%,92% "$TMP/mask.png"
  magick "$1" "$TMP/mask.png" -alpha off -compose CopyOpacity -composite "$2"
}

# 顶/底可读性暗带
add_bands() { # $1=in $2=out — 顶/底暗带 (gravity 必须显式! 否则落在 NorthWest/残留位置)
  magick -size ${W}x260 "gradient:${BAND}-none" "$TMP/top.png"
  magick -size ${W}x150 "gradient:none-${BAND}" "$TMP/bot.png"
  magick "$1" "$TMP/top.png" -gravity North -compose Over -composite \
    "$TMP/bot.png" -gravity South -compose Over -composite "$2"
}

mkdir -p "$OUT"

if [[ $KIND == direct ]]; then
  SRC="$DIR/src/wallpaper.img"
  [[ -f $SRC ]] || { echo "缺 $SRC"; exit 1; }
  magick "$SRC" -resize ${W}x${H}^ -gravity center -extent ${W}x${H} "$TMP/wall.png"
  add_bands "$TMP/wall.png" "$OUT/1-${SLUG}.jpg"
else
  # 模糊延展合成: 立绘自身模糊铺满做底, 中央原生立绘羽化融入
  # (比渐变底自然: 边缘色彩来自立绘, 无生硬色块接缝)
  ART="$DIR/src/art.png"
  [[ -f $ART ]] || { echo "缺 $ART"; exit 1; }
  th=$(art_target_h "$ART")
  magick "$ART" -resize x${th} -filter Lanczos "$TMP/art.png"
  # 底: 立绘 cover 铺满 + 重模糊 + 压暗, 微噪防色带
  magick "$ART" -resize ${W}x${H}^ -gravity center -extent ${W}x${H} \
    -blur 0x50 -modulate 55,115,100 -attenuate 0.1 +noise Gaussian "$TMP/bg.png"
  feather "$TMP/art.png" "$TMP/artf.png" 180
  magick "$TMP/bg.png" "$TMP/artf.png" -gravity center -compose Over -composite "$TMP/wall.png"
  add_bands "$TMP/wall.png" "$OUT/5-composed.jpg"
fi

# 第二张: 纯渐变抽象壁纸 (供 bg next 换口味)
magick -size ${W}x${H} "gradient:${DBG}-${BG}" "$TMP/base.png"
magick -size ${W}x${H} "radial-gradient:${ACC}-none" -channel A -evaluate multiply 0.13 +channel "$TMP/glow.png"
magick "$TMP/base.png" "$TMP/glow.png" -compose Screen -composite \
  -attenuate 0.12 +noise Gaussian "$TMP/base2.png"
add_bands "$TMP/base2.png" "$OUT/2-abstract.jpg"
identify -format "%f %wx%h\n" "$OUT"/*.jpg
