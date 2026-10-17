#!/usr/bin/env bash
# gamemode: игра закрылась — возвращаем видеообои
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper.cmd"
[ -s "$state" ] || exit 0
pgrep -x mpvpaper >/dev/null && exit 0

# gamemoded живёт в systemd --user, там нет окружения Hyprland
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi

cmd=""
while IFS= read -r -d '' arg; do cmd+=" $(printf '%q' "$arg")"; done < "$state"
# старый формат конфига: «dispatch exec …»; новый (hyprland.lua): «dispatch hl.dsp.exec_cmd(…)»
out=$(hyprctl dispatch exec "$cmd" 2>&1)
[ "$out" = ok ] || out=$(hyprctl dispatch "hl.dsp.exec_cmd([==[$cmd]==])" 2>&1)
[ "$out" = ok ] && rm -f "$state"
