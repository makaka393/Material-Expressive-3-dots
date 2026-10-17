#!/usr/bin/env bash
# Запускает команду, только если активное окно не в полноэкранном режиме:
# в игре случайный SUPER+клавиша не должен открывать лаунчер, обои и т.п.
hyprctl activewindow -j | jq -e '.fullscreen >= 2' >/dev/null 2>&1 && exit 0
exec "$@"
