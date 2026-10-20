#!/usr/bin/env bash
# Игровой режим: игра запустилась — убираем видеообои, душим фоновые прожорливые процессы, усыпляем
# локальный ИИ. Зовут gamemode (игры через gamemoderun) и game-watch.sh (оболочка сама находит игры
# Steam, Proton и Mobile Legends). Повторный вызов ничего не портит.
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# метка «идёт игра»: по ней ассистент выгружает Whisper и локальную модель (до 4 ГБ видеопамяти;
# слово-активатор гонял Whisper на звуке игры — до целого ядра) и не слушает, пока она есть.
# В метке — кто включил: watch (game-watch.sh) или gamemode
[ -e "$run/glass-game" ] || echo "${GLASS_GAME_BY:-gamemode}" > "$run/glass-game"

# видеообои (~1 ГБ видеопамяти и декодирование): под ними и так лежит их кадр (awww).
# Вернёт gamemode-end.sh — через changetheme.sh --restore
pkill -x mpvpaper

# без root приоритет можно только понизить; вернётся при перезапуске приложения
for p in $(pgrep -x spotify; pgrep -x Discord); do
    renice -n 10 -p "$p" >/dev/null
done
