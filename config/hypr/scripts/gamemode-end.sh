#!/usr/bin/env bash
# Игровой режим: игра закрылась — ассистент просыпается (снята метка), возвращаем видеообои.
# Зовут gamemode и game-watch.sh (см. gamemode-start.sh)
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
rm -f "$run/glass-game" "$run/mpvpaper.cmd"      # mpvpaper.cmd — от прежней версии

# видеообои — тем же путём, что после входа (changetheme.sh --restore), если обои — видео
case "$(readlink -f "$HOME/.cache/matugen/wallpaper" 2>/dev/null)" in
    *.[mM][pP]4|*.[wW][eE][bB][mM]|*.[mM][kK][vV]|*.[mM][oO][vV]) ;;
    *) exit 0 ;;
esac
pgrep -x mpvpaper >/dev/null && exit 0

# gamemoded живёт в systemd --user, там нет окружения Hyprland: обои запускаем через Hyprland
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$run/hypr" | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi
cmd="$HOME/.config/hypr/scripts/changetheme.sh --restore"
# старый формат конфига: «dispatch exec …»; новый (hyprland.lua): «dispatch hl.dsp.exec_cmd(…)»
out=$(hyprctl dispatch exec "$cmd" 2>&1)
[ "$out" = ok ] || hyprctl dispatch "hl.dsp.exec_cmd([==[$cmd]==])" >/dev/null 2>&1
