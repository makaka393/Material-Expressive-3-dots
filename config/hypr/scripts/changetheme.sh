#!/usr/bin/env bash
# changetheme.sh — обои (картинка / GIF / видео) + Material 3 палитра (matugen)
#
#   changetheme.sh <обои>                 палитра из обоев
#   changetheme.sh <обои> "#ff5588"       обои + палитра от своего цвета
#   changetheme.sh "#ff5588"              только сменить цвета, обои не трогать
#   changetheme.sh --restore              после входа: снова запустить видео-обои
#
# Картинки и GIF ставит awww, видео (.mp4 .webm .mkv .mov) крутит mpvpaper.
# Настройки — ~/.config/hypr/scripts/theme.env (SCHEME, CONTRAST, MODE)
set -euo pipefail

ENV_FILE="$HOME/.config/hypr/scripts/theme.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
SCHEME="${SCHEME:-scheme-vibrant}"
CONTRAST="${CONTRAST:-0.3}"
MODE="${MODE:-dark}"
STATE="$HOME/.cache/matugen"
mkdir -p "$STATE"

die() { timeout 2 notify-send -u critical "changetheme" "$1" 2>/dev/null || true; echo "$1" >&2; exit 1; }
is_video() { case "${1,,}" in *.mp4|*.webm|*.mkv|*.mov) return 0;; *) return 1;; esac; }

start_video() {
  pkill -x mpvpaper 2>/dev/null || true
  # -f: в фоне, -p: пауза, когда обои закрыты окнами (экономит видеокарту)
  mpvpaper -f -p -o "no-audio loop hwdec=auto panscan=1.0 really-quiet cache=no demuxer-max-bytes=16MiB demuxer-max-back-bytes=4MiB vd-lavc-threads=2" ALL "$1" >/dev/null 2>&1 || true
}

ensure_awww() {
  if ! awww query >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 20); do awww query >/dev/null 2>&1 && break; sleep 0.1; done
  fi
}

# ---- после входа: вернуть видео-обои
if [ "${1:-}" = "--restore" ]; then
  WP=$(readlink -f "$STATE/wallpaper" 2>/dev/null || true)
  [ -n "$WP" ] && [ -f "$WP" ] && is_video "$WP" && start_video "$WP"
  exit 0
fi

[ $# -ge 1 ] || die "Использование: changetheme.sh <обои> [#hex]  |  changetheme.sh #hex"

WALLPAPER=""; COLOR=""
for arg in "$@"; do
  if [[ "$arg" =~ ^#?[0-9a-fA-F]{6}$ ]]; then COLOR="#${arg#\#}"
  elif [ "$arg" = mono ]; then COLOR=mono
  else WALLPAPER=$(realpath "$arg"); [ -f "$WALLPAPER" ] || die "Файл не найден: $arg"; fi
done

# ---- кадр, с которого берём цвета
SRC="$WALLPAPER"
if [ -n "$WALLPAPER" ]; then
  if is_video "$WALLPAPER"; then
    ffmpeg -nostdin -y -loglevel error -ss 1 -i "$WALLPAPER" -frames:v 1 -vf "scale=1280:-2" "$STATE/frame.png" 2>/dev/null \
      || ffmpeg -nostdin -y -loglevel error -i "$WALLPAPER" -frames:v 1 -vf "scale=1280:-2" "$STATE/frame.png" \
      || die "Не смог вытащить кадр из видео"
    SRC="$STATE/frame.png"
  else
    case "${WALLPAPER,,}" in
      *.gif|*.webp) magick "${WALLPAPER}[0]" -resize 1280x "$STATE/frame.png" && SRC="$STATE/frame.png" ;;
    esac
  fi
fi

# ---- обои
if [ -n "$WALLPAPER" ]; then
  ensure_awww
  SAME=0; [ "$(readlink -f "$STATE/wallpaper" 2>/dev/null)" = "$WALLPAPER" ] && SAME=1
  if [ $SAME = 1 ] && { ! is_video "$WALLPAPER" || pgrep -x mpvpaper >/dev/null; }; then
    :   # эти обои уже стоят (сменили только цвет/схему) — без повторного перехода
  elif is_video "$WALLPAPER"; then
    # под видео кладём его кадр — красивый переход и запасной фон
    awww img "$SRC" --transition-fps 60 --transition-type grow \
         --transition-pos 0.5,0.5 --transition-duration 1.0
    sleep 0.6
    start_video "$WALLPAPER"
  else
    pkill -x mpvpaper 2>/dev/null || true
    awww img "$WALLPAPER" --transition-fps 60 --transition-type grow \
         --transition-pos 0.5,0.5 --transition-duration 1.2
  fi
  ln -sf "$WALLPAPER" "$STATE/wallpaper"   # для бара/пикера/--restore
fi

# ---- палитра
# белый/серый/чёрный цвет и «mono» → чёрно-белая тема (иначе matugen делает из белого голубой)
MONO=0
if [ "$COLOR" = mono ]; then MONO=1
elif [ -n "$COLOR" ]; then
  R=$((16#${COLOR:1:2})); G=$((16#${COLOR:3:2})); B=$((16#${COLOR:5:2}))
  MX=$R; [ $G -gt $MX ] && MX=$G; [ $B -gt $MX ] && MX=$B
  MN=$R; [ $G -lt $MN ] && MN=$G; [ $B -lt $MN ] && MN=$B
  [ $((MX - MN)) -le 24 ] && MONO=1
fi
MGCFG=()
if [ $MONO = 1 ] || [ "$SCHEME" = scheme-monochrome ]; then
  SCHEME=scheme-monochrome
  # у kitty в конфиге matugen своя схема (tonal spot) — для ч/б убираем, иначе терминал станет цветным
  MGT=$(mktemp); sed '/^type *= *"Scheme/d' "$HOME/.config/matugen/config.toml" > "$MGT"; MGCFG=(-c "$MGT")
fi
ARGS=(-m "$MODE" -t "$SCHEME" --contrast "$CONTRAST" -q "${MGCFG[@]}")
if [ -n "$COLOR" ]; then
  if [ "$COLOR" = mono ]; then matugen color hex "#808080" "${ARGS[@]}"; else matugen color hex "$COLOR" "${ARGS[@]}"; fi
  echo "$COLOR" > "$STATE/source"
elif [ -n "$WALLPAPER" ]; then
  matugen image "$SRC" --source-color-index 0 "${ARGS[@]}"
  rm -f "$STATE/source"
fi

# «Точный цвет» (настройки): primary = ровно выбранный цвет, а не пастельный вариант Material
if [ -n "$COLOR" ] && [ "$COLOR" != mono ] && [ "${MONO:-0}" = 0 ] && python3 -c \
  'import json,os,sys; sys.exit(0 if json.load(open(os.path.expanduser("~/.config/glass/settings.json"))).get("exactColor") else 1)' 2>/dev/null; then
  python3 "$HOME/.config/hypr/scripts/exact-accent.py" "$COLOR" || true
fi

# ---- применить
timeout 2 gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODE" 2>/dev/null || true
hyprctl reload >/dev/null
pkill -SIGUSR1 kitty 2>/dev/null || true
pkill -USR2 -x btop 2>/dev/null || true   # btop перечитывает тему без перезапуска
# медленное (KDE, папки Papirus, экран входа) — в фоне: бар и окна перекрашиваются сразу
(
# KDE/Qt-приложения (Dolphin и др.): цветовая схема + иконки под тему
if command -v plasma-apply-colorscheme >/dev/null && [ -f "$HOME/.local/share/color-schemes/Matugen.colors" ]; then
  CS="$HOME/.local/share/color-schemes"
  # KDE не применяет схему повторно с тем же именем — чередуем Matugen / MatugenAlt
  if [ "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)" = "Matugen" ]; then
    NEXT=MatugenAlt
    sed 's/^ColorScheme=Matugen$/ColorScheme=MatugenAlt/; s/^Name=Matugen$/Name=MatugenAlt/' "$CS/Matugen.colors" > "$CS/MatugenAlt.colors"
  else
    NEXT=Matugen
  fi
  timeout 5 plasma-apply-colorscheme "$NEXT" >/dev/null 2>&1 || true
  # папки Papirus в акцентный цвет темы
  python3 "$HOME/.config/hypr/scripts/folder-colors.py" "$MODE" >/dev/null 2>&1 || true
  ICONS=Papirus-Matugen
  [ -d "$HOME/.local/share/icons/Papirus-Matugen" ] || { ICONS=Papirus-Dark; [ "$MODE" = light ] && ICONS=Papirus-Light; }
  [ -d "/usr/share/icons/$ICONS" ] || [ -d "$HOME/.local/share/icons/$ICONS" ] || { [ "$MODE" = light ] && ICONS=breeze || ICONS=breeze-dark; }
  kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICONS" 2>/dev/null || true
  # сказать KDE-приложениям перечитать иконки без перезапуска
  rm -f "$HOME/.cache/icon-cache.kcache"
  dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged int32:0 2>/dev/null || true
fi
# ---- экран входа SDDM (тема glass): те же цвета и обои — только пока SDDM включён
# (вместо него может быть экран блокировки оболочки: lockscreen-instead-of-sddm.sh)
SDDM_USER=/usr/share/sddm/themes/glass/user
if systemctl -q is-enabled sddm 2>/dev/null && [ -d "$SDDM_USER" ] && [ -w "$SDDM_USER" ] && [ -f "$STATE/sddm-colors.conf" ]; then
  WP=$(readlink -f "$STATE/wallpaper" 2>/dev/null || true)
  if [ -n "$WP" ] && [ -f "$WP" ] && [ "$(cat "$SDDM_USER/.src" 2>/dev/null || true)" != "$WP" ]; then
    rm -f "$SDDM_USER"/bg.* "$SDDM_USER/frame.jpg"
    EXT="${WP##*.}"; EXT="${EXT,,}"
    cp -f "$WP" "$SDDM_USER/bg.$EXT"
    if is_video "$WP"; then   # кадр из видео — пока ролик не запустился
      ffmpeg -nostdin -y -loglevel error -ss 1 -i "$WP" -frames:v 1 -q:v 3 "$SDDM_USER/frame.jpg" 2>/dev/null \
        || ffmpeg -nostdin -y -loglevel error -i "$WP" -frames:v 1 -q:v 3 "$SDDM_USER/frame.jpg" 2>/dev/null || true
    fi
    chmod 644 "$SDDM_USER"/bg.* "$SDDM_USER/frame.jpg" 2>/dev/null || true
    printf '%s\n' "$WP" > "$SDDM_USER/.src"
  fi
  BGF=$(ls "$SDDM_USER"/bg.* 2>/dev/null | head -n1 || true)
  {
    echo "[General]"
    cat "$STATE/sddm-colors.conf"
    if [ -n "$BGF" ] && is_video "$BGF"; then
      echo "video=$BGF"; echo "background=$SDDM_USER/frame.jpg"
    else
      echo "video="; echo "background=$BGF"
    fi
  } > "$SDDM_USER/theme.conf.user.new"
  mv -f "$SDDM_USER/theme.conf.user.new" "$SDDM_USER/theme.conf.user"
  chmod 644 "$SDDM_USER/theme.conf.user" 2>/dev/null || true
fi
) >/dev/null 2>&1 &
disown
# Quickshell перечитает ~/.cache/matugen/colors.json сам

timeout 2 notify-send -a changetheme -i "${SRC:-preferences-desktop-theme}" \
  "Тема обновлена" "$SCHEME · контраст $CONTRAST" 2>/dev/null || true
