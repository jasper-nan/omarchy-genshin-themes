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
magick_base() {
  # 基础渐变: 顶部深色 -> 底部主题底色, 加强调色辉光与微噪点
  magick -size ${W}x${H} "gradient:${DBG}-${BG}" "$TMP/base.png"
  magick -size ${W}x${H} "radial-gradient:${ACC}-none" "$TMP/glow.png"
  magick "$TMP/glow.png" -channel A -evaluate multiply 0.13 +channel "$TMP/glow.png"
  magick "$TMP/base.png" "$TMP/glow.png" -compose Screen -composite \
    -attenuate 0.12 +noise Gaussian "$TMP/base2.png"
}

feather() { # $1=in $2=out — 边缘羽化蒙版
  local aw ah; read -r aw ah < <(identify -format '%w %h\n' "$1" || true)
  magick -size ${aw}x${ah} xc:white -shave 100x100 \
    -bordercolor black -border 100 -blur 0x70 "$TMP/mask.png"
  magick "$1" "$TMP/mask.png" -alpha off -compose CopyOpacity -composite "$2"
}

add_bands() { # $1=in $2=out — 顶/底可读性渐变带 + 整体轻噪点
  magick -size ${W}x260 "gradient:${BAND}-none" "$TMP/top.png"
  magick -size ${W}x150 "gradient:none-${BAND}" "$TMP/bot.png"
  magick "$1" "$TMP/top.png" -compose Over -composite \
    "$TMP/bot.png" -compose Over -composite "$2"
}

mkdir -p "$OUT"

if [[ $KIND == direct ]]; then
  SRC="$DIR/src/wallpaper.img"
  [[ -f $SRC ]] || { echo "缺 $SRC"; exit 1; }
  # 先统一缩放到标准 4K (小图放大, 超大缩小)
  magick "$SRC" -resize ${W}x${H}^ -gravity center -extent ${W}x${H} "$TMP/wall.png"
  add_bands "$TMP/wall.png" "$OUT/1-${SLUG}.png"
else
  ART="$DIR/src/art.png"
  [[ -f $ART ]] || { echo "缺 $ART"; exit 1; }
  magick_base
  # 立绘: 目标高度 = 画布 88%, 但放大倍率受源尺寸限制 (大图≤1.35x, 小图≤1.6x)
  read -r aw ah < <(identify -format '%w %h\n' "$ART" || true)
  cap=1.35; (( aw < 1500 )) && cap=1.6
  target_h=$(python3 -c "print(min(int($H*0.88), int($ah*$cap)))")
  magick "$ART" -resize x${target_h} -filter Lanczos "$TMP/art.png"
  feather "$TMP/art.png" "$TMP/artf.png"
  magick "$TMP/base2.png" "$TMP/artf.png" -gravity center -compose Over -composite "$TMP/wall.png"
  add_bands "$TMP/wall.png" "$OUT/1-${SLUG}.png"
fi

# 第二张: 纯渐变抽象壁纸 (供 bg next 换口味)
magick_base
add_bands "$TMP/base2.png" "$OUT/2-abstract.png"
identify -format "%f %wx%h\n" "$OUT/1-${SLUG}.png" "$OUT/2-abstract.png"
