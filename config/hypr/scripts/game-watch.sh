#!/usr/bin/env bash
# Игровой режим без gamemoderun: оболочка (Games.qml) запускает это раз в 3 с. Игра — процесс из папки
# игр Steam (свои и через Proton: Dota 2, CS2…) или Mobile Legends в Waydroid (cage_xtmapper); свои
# шаблоны — в ~/.config/glass/games, по одному на строку (регулярное выражение по командной строке).
# Нашлась — gamemode-start.sh, закрылась — gamemode-end.sh. Состояние — метка $XDG_RUNTIME_DIR/glass-game:
# перезапуск оболочки ничего не путает, а режим, который включил gamemode, он сам и выключает.
# Печатает имя игры (или ничего).
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mark="$run/glass-game"
here="$(dirname "$(readlink -f "$0")")"

pat='/steamapps/common/|cage_xtmapper'
extra="$HOME/.config/glass/games"
if [ -s "$extra" ]; then
    more=$(grep -v '^[[:space:]]*\(#\|$\)' "$extra" | paste -sd'|')
    [ -n "$more" ] && pat="$pat|$more"
fi

# процессы игры; оболочки и утилиты, у которых путь Steam просто в аргументах, не в счёт
procs=$(pgrep -u "$(id -u)" -l -f "$pat" | awk '$2 !~ /^(zsh|bash|sh|fish|grep|rg|pgrep|find|nvim|vim|less|tail|cat|ls|du|cp|mv|rsync)$/')
# имя — самого игрового процесса, а не обёрток Steam (reaper, pressure-vessel, *.sh)
game=$(printf '%s\n' "$procs" | awk 'NF && $2 !~ /^(reaper|srt-bwrap|pv-adverb|bwrap|steam-runtime|python3?)$/ && $2 !~ /\.sh$/ { print $2; exit }')
[ -z "$game" ] && [ -n "$procs" ] && game=game

if [ -n "$game" ]; then
    if [ -e "$mark" ]; then
        pkill -x mpvpaper                  # обои сменили посреди игры — видео всё равно не крутим
    else
        GLASS_GAME_BY=watch "$here/gamemode-start.sh"
    fi
    echo "$game"
elif [ "$(cat "$mark" 2>/dev/null)" = watch ]; then
    "$here/gamemode-end.sh"
fi
