#!/usr/bin/env bash
# screenshot.sh [region|full|pretty]
#   region — выделить область (SUPER+SHIFT+S)
#   full   — весь экран (Print)
#   pretty — область в красивой рамке: скругления, тень, градиент из цветов темы (SUPER+SHIFT+A)
#   lens   — выделить область и отправить в Google Lens (или покрутить мышкой по кругу)
# Выделение — скруглённая рамка + свечение по краям экрана (~/.config/quickshell/glow), сам снимок обычный.
# Сохраняет в ~/Pictures/Screenshots и копирует в буфер.
set -euo pipefail
MODE="${1:-region}"
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
F="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"

# цвета темы из matugen
eval "$(python3 - <<'PY'
import json, os
try: c = json.load(open(os.path.expanduser("~/.cache/matugen/colors.json")))
except Exception: c = {}
g = lambda k, d: c.get(k, d).lstrip("#")
print(f'P={g("primary","a8c7fa")} PC={g("primaryContainer","284777")} T={g("tertiary","ddbce0")} S={g("surfaceLowest","0c0e13")}')
PY
)"

# скругление углов через Pillow — одинаково работает с любой версией ImageMagick
round_png() {   # $1 вход  $2 выход  $3 радиус
  python3 - "$1" "$2" "$3" <<'PY'
import sys
from PIL import Image, ImageDraw
src, dst, r = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")
w, h = im.size
r = max(2, min(r, min(w, h) // 3))
s = 4                                     # рисуем маску в 4× и уменьшаем — гладкие края
mask = Image.new("L", (w * s, h * s), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius=r * s, fill=255)
mask = mask.resize((w, h), Image.LANCZOS)
im.putalpha(mask)
im.save(dst, "PNG")
PY
}

beautify() {   # скругления, обводка, тень, градиентный фон
  local W H R PAD TMP
  read -r W H < <(magick identify -format "%w %h\n" "$F")
  R=$(( (W < H ? W : H) / 20 )); [ "$R" -gt 24 ] && R=24; [ "$R" -lt 8 ] && R=8
  PAD=$(( (W > H ? W : H) / 12 )); [ "$PAD" -lt 48 ] && PAD=48
  TMP=$(mktemp -d)
  round_png "$F" "$TMP/r.png" "$R"
  magick "$TMP/r.png" -fill none -stroke "#${P}66" -strokewidth 2 \
         -draw "roundrectangle 1,1,$((W-2)),$((H-2)),$R,$R" "$TMP/r.png"
  magick "$TMP/r.png" \( +clone -background black -shadow 55x$((PAD/3))+0+$((PAD/8)) \) +swap \
         -background none -layers merge +repage "$TMP/s.png"
  magick -size "$((W + PAD*2))x$((H + PAD*2))" -define gradient:angle=135 \
         gradient:"#${PC}"-"#${T}" "$TMP/s.png" -gravity center -composite -depth 8 "$F"
  rm -rf "$TMP"
}

lens_send() {   # открывает Google Lens с картинкой в браузере по умолчанию
  local D="$HOME/.cache/lens" J H
  mkdir -p "$D"; find "$D" -type f -mmin +30 -delete 2>/dev/null
  J="$D/shot.jpg"; H="$D/upload-$(date +%s).html"
  magick "$F" -quality 92 "$J"
  python3 - "$J" "$H" <<'PY'
import base64, sys
b = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
open(sys.argv[2], "w").write("""<!doctype html><meta charset=utf-8><title>Google Lens</title>
<body style="margin:0;background:#131314;color:#c4c7c5;font:16px sans-serif;display:grid;place-items:center;height:100vh">
Отправляю в Google Lens…
<form id=f method=POST enctype=multipart/form-data action="https://lens.google.com/v3/upload?hl=ru">
<input type=file name=encoded_image id=i hidden></form>
<script>
const b = atob("%s"), a = new Uint8Array(b.length);
for (let k = 0; k < b.length; k++) a[k] = b.charCodeAt(k);
const dt = new DataTransfer();
dt.items.add(new File([a], "screenshot.jpg", { type: "image/jpeg" }));
document.getElementById("i").files = dt.files;
document.getElementById("f").submit();
</script>""" % b)
PY
  xdg-open "$H" >/dev/null 2>&1 &
}

# мини-шелл со свечением и выделением (qs -c glow); если не запущен — запускаем
qsglow() {
  qs ipc -c glow call "$@" >/dev/null 2>&1 && return 0
  qs -c glow -n -d >/dev/null 2>&1; sleep 0.8
  qs ipc -c glow call "$@" >/dev/null 2>&1
}

case "$MODE" in
  full)
    grim "$F" ;;

  region|pretty|lens)
    # красивое выделение: скруглённая рамка + свечение по краям; результат придёт как «capture»
    MON=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitor"])')
    qsglow shot start "$MODE" "$MON" && exit 0
    # запасной вариант — обычный slurp
    G=$(slurp -d -b "${S}88" -c "${P}ff" -s "${P}1f" -B "${P}55" -w 3) || exit 0
    grim -g "$G" "$F"
    [ "$MODE" = pretty ] && beautify
    [ "$MODE" = lens ] && lens_send ;;

  capture)   # вызывается выделением: capture <region|pretty|lens> "x,y wxh"
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/shake-lens.lock"
    sleep 0.25                       # выделение и свечение успевают исчезнуть
    grim -g "$3" "$F"
    [ "$2" = pretty ] && beautify
    [ "$2" = lens ] && lens_send ;;

  *) echo "режимы: region | full | pretty | lens"; exit 1 ;;
esac

wl-copy --type image/png < "$F"
timeout 3 qs ipc -c glass call island screenshot "$F" >/dev/null 2>&1 || true
timeout 2 notify-send -a "Скриншот" -i "$F" "Скриншот готов" "$(basename "$F") · скопирован в буфер" 2>/dev/null || true
