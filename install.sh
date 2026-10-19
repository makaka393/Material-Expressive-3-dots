#!/usr/bin/env bash
# Намира ОС (glass-dots) — установка. Запуск из папки репозитория: ./install.sh
#   --no-packages   не ставить пакеты
#   --no-sddm       не трогать экран входа
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
R="$PWD"
ME="$(id -un)"
PKGS=1; SDDM=1
for a in "$@"; do case "$a" in --no-packages) PKGS=0;; --no-sddm) SDDM=0;; esac; done

# ───────────── пакеты
if [ $PKGS = 1 ]; then
  echo ":: пакеты"
  REPO=(hyprland grim slurp wl-clipboard imagemagick ffmpeg python python-pillow btop kitty rofi
        papirus-icon-theme qt6-5compat qt6-multimedia-ffmpeg qt6-declarative libnotify wireplumber libpulse
        curl git mpv xdg-utils)
  [ $SDDM = 1 ] && REPO+=(sddm xorg-xrandr)
  MAYBE_AUR=(quickshell matugen awww mpvpaper)   # где-то в репах, где-то в AUR
  sudo pacman -S --needed --noconfirm "${REPO[@]}"
  AUR=""; command -v yay >/dev/null && AUR=yay; command -v paru >/dev/null && AUR=${AUR:-paru}
  for p in "${MAYBE_AUR[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 && continue
    if pacman -Si "$p" >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm "$p"
    elif [ -n "$AUR" ]; then $AUR -S --needed --noconfirm "$p" || echo "!! не поставился $p"
    else echo "!! $p есть только в AUR — поставь yay/paru и запусти ещё раз"; fi
  done
fi

# ───────────── конфиги (со бэкапом того, что перезапишем)
echo ":: конфиги"
BK="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
(cd "$R/config" && find . -type f) | while IFS= read -r f; do
  dst="$HOME/.config/${f#./}"
  if [ -e "$dst" ] && ! cmp -s "$R/config/$f" "$dst"; then mkdir -p "$BK/$(dirname "${f#./}")"; cp -a "$dst" "$BK/${f#./}"; fi
  mkdir -p "$(dirname "$dst")"
  cp "$R/config/$f" "$dst"
done
[ -d "$BK" ] && echo "   старые файлы: $BK"
chmod +x "$HOME/.config/hypr/scripts/"*.sh "$HOME/.config/hypr/scripts/"*.py 2>/dev/null || true
mkdir -p "$HOME/.cache/matugen"

# ───────────── шрифты: Google Sans Flex + Material Symbols Rounded
FONTS="$HOME/.local/share/fonts"; mkdir -p "$FONTS"
get_font() {
  [ -n "$(find "$FONTS" /usr/share/fonts -iname "$2" 2>/dev/null | head -n1 || true)" ] && return 0
  echo "   качаю $1"; curl -fL --progress-bar -o "$FONTS/$1" "$3"
}
get_font GoogleSansFlex.ttf "GoogleSansFlex*.ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/googlesansflex/GoogleSansFlex%5BGRAD,ROND,opsz,slnt,wdth,wght%5D.ttf"
get_font MaterialSymbolsRounded.ttf "MaterialSymbolsRounded*.ttf" \
  "https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"
fc-cache -f "$FONTS" >/dev/null 2>&1 || true

# ───────────── обои для примера → папка из Theme.qml
WD=$(grep -oP 'wallpaperDir:.*\+\s*"\K[^"]+' "$HOME/.config/quickshell/glass/Theme.qml" 2>/dev/null | head -n1 || true)
WD="$HOME${WD:-/Pictures/Wallpapers}"
mkdir -p "$WD"
cp -n "$R"/wallpapers/* "$WD/" 2>/dev/null || true

# ───────────── экран входа SDDM
if [ $SDDM = 1 ] && [ -d "$R/sddm/glass" ]; then
  echo ":: экран входа SDDM"
  D=/usr/share/sddm/themes/glass
  sudo mkdir -p "$D/user" "$D/fonts"
  sudo cp -r "$R/sddm/glass/." "$D/"
  sudo cp "$(find "$FONTS" /usr/share/fonts -iname 'GoogleSansFlex*.ttf' | head -n1)" "$D/fonts/GoogleSansFlex.ttf"
  sudo cp "$(find "$FONTS" /usr/share/fonts -iname 'MaterialSymbolsRounded*.ttf' | head -n1)" "$D/fonts/MaterialSymbolsRounded.ttf"
  LAT=$(grep -oP 'property real lat:\s*\K[0-9.\-]+' "$HOME/.config/quickshell/glass/Theme.qml" 2>/dev/null || true)
  LON=$(grep -oP 'property real lon:\s*\K[0-9.\-]+' "$HOME/.config/quickshell/glass/Theme.qml" 2>/dev/null || true)
  [ -n "$LAT" ] && sudo sed -i "s/^lat=.*/lat=$LAT/" "$D/theme.conf"
  [ -n "$LON" ] && sudo sed -i "s/^lon=.*/lon=$LON/" "$D/theme.conf"
  sudo chown -R root:root "$D"; sudo chmod -R a+rX "$D"
  sudo chown -R "$ME:$ME" "$D/user"; sudo chmod 755 "$D/user"
  sudo ln -sfn user/theme.conf.user "$D/theme.conf.user"
  CONF='[Theme]\nCurrent=glass\n'
  if [ -f "$R/sddm/Xsetup" ]; then
    sudo install -Dm755 "$R/sddm/Xsetup" /usr/local/lib/sddm-glass/Xsetup
    CONF="$CONF"'\n[X11]\nDisplayCommand=/usr/local/lib/sddm-glass/Xsetup\n'
  fi
  sudo mkdir -p /etc/sddm.conf.d
  printf "$CONF" | sudo tee /etc/sddm.conf.d/99-glass-theme.conf >/dev/null
  systemctl is-enabled sddm >/dev/null 2>&1 || echo "   (sddm не включён: sudo systemctl enable sddm)"
fi

# ───────────── первая тема
echo ":: применяю тему"
FIRST=$(find "$WD" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) | head -n1 || true)
CUR=$(readlink -f "$HOME/.cache/matugen/wallpaper" 2>/dev/null || true)
[ -n "$CUR" ] && [ -f "$CUR" ] && FIRST="$CUR"
if [ -n "$FIRST" ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  "$HOME/.config/hypr/scripts/changetheme.sh" "$FIRST" || true
  qs kill -c glass >/dev/null 2>&1 || true; qs -c glass -n -d >/dev/null 2>&1 || true
  qs kill -c glow >/dev/null 2>&1 || true; qs -c glow -n -d >/dev/null 2>&1 || true
else
  echo "   запусти из Hyprland: ~/.config/hypr/scripts/changetheme.sh <обои>"
fi

echo
echo "Готово. Перезайди в Hyprland (или перезагрузись, чтобы увидеть экран входа)."
