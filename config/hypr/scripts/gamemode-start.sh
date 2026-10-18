#!/usr/bin/env bash
# gamemode: игра запустилась — убираем видеообои и душим фоновые прожорливые процессы
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper.cmd"

pid=$(pgrep -xo mpvpaper)
if [ -n "$pid" ]; then
    cp "/proc/$pid/cmdline" "$state"
    kill "$pid"
fi

# без root приоритет можно только понизить; вернётся при перезапуске приложения
for p in $(pgrep -x spotify; pgrep -x Discord; pgrep -x mpvpaper); do
    renice -n 10 -p "$p" >/dev/null
done

# локальная модель ассистента держит ~3 ГБ видеопамяти — игре нужнее (загрузится снова по Super+A)
qs ipc -c glass call assistant unload >/dev/null 2>&1 || true
