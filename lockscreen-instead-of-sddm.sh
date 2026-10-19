#!/usr/bin/env bash
# Намира ОС (glass-dots) — экран блокировки оболочки вместо SDDM.
#   ./lockscreen-instead-of-sddm.sh          включить (сработает после перезагрузки)
#   ./lockscreen-instead-of-sddm.sh --undo   вернуть SDDM (если пакет удалён — поставит заново)
#
# Как это устроено: на tty1 включается автовход, оттуда запускается Hyprland, а оболочка
# первым делом запирает экран (lockOnStart) — пароль вводится на экране блокировки с обоями.
# Что стоит знать: сессия при этом уже запущена за замком (автозапуск приложений идёт до ввода
# пароля), а между стартом Hyprland и замком рабочий стол виден на долю секунды.
# Если что-то пошло не так: Ctrl+Alt+F2 → вход в консоль → ./lockscreen-instead-of-sddm.sh --undo
set -euo pipefail

ME="$(id -un)"
DROPIN=/etc/systemd/system/getty@tty1.service.d/glass-autologin.conf
SETTINGS="$HOME/.config/glass/settings.json"
BEGIN="# >>> glass: Hyprland на tty1 >>>"
END="# <<< glass <<<"
case "$(getent passwd "$ME" | cut -d: -f7)" in
  */zsh) PROFILE="$HOME/.zprofile" ;;
  *)     PROFILE="$HOME/.bash_profile" ;;
esac

set_lock_on_start() {
  python3 - "$SETTINGS" "$1" <<'PY'
import json, sys
p, v = sys.argv[1], sys.argv[2] == "true"
d = json.load(open(p))
d["lockOnStart"] = v
json.dump(d, open(p, "w"), indent=4)
PY
}
strip_profile() {
  [ -f "$PROFILE" ] || return 0
  sed -i "/^$BEGIN\$/,/^$END\$/d" "$PROFILE"
}

if [ "${1:-}" = "--undo" ]; then
  echo ":: возвращаю SDDM"
  sudo rm -f "$DROPIN"
  sudo rmdir --ignore-fail-on-non-empty "$(dirname "$DROPIN")" 2>/dev/null || true
  sudo systemctl daemon-reload
  pacman -Qq sddm >/dev/null 2>&1 || sudo pacman -S --needed sddm
  sudo systemctl enable sddm
  strip_profile
  set_lock_on_start false
  echo "Готово. После перезагрузки снова будет экран входа SDDM."
  exit 0
fi

command -v start-hyprland >/dev/null || { echo "!! не найден start-hyprland"; exit 1; }
[ -f "$SETTINGS" ] || { echo "!! нет $SETTINGS — оболочка glass ещё не запускалась"; exit 1; }

# пароль экрана блокировки проверяем до того, как от него будет зависеть вход
LOCKED="${XDG_RUNTIME_DIR:-/tmp}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/glass-locked"
echo "Сначала проверим, что экран блокировки принимает твой пароль: экран запрётся,"
echo "введи пароль (если не ввести — замок сам снимется через 15 секунд)."
read -r -p "Запереть на проверку? [Y/n] " a
if [ "$a" != n ] && [ "$a" != N ]; then
  qs ipc -c glass call lock test >/dev/null || { echo "!! оболочка glass не отвечает"; exit 1; }
  sleep 1
  for _ in $(seq 40); do [ -e "$LOCKED" ] || break; sleep 0.5; done
fi
read -r -p "Пароль подошёл, продолжать? [y/N] " a
[ "$a" = y ] || [ "$a" = Y ] || { echo "Отменено."; exit 1; }

echo ":: автовход на tty1"
sudo mkdir -p "$(dirname "$DROPIN")"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o '"'"'-p -f -- \\\\u'"'"' --noclear --autologin %s %%I $TERM\n' "$ME" \
  | sudo tee "$DROPIN" >/dev/null
sudo systemctl daemon-reload

echo ":: запуск Hyprland при входе на tty1 ($PROFILE)"
strip_profile
cat >> "$PROFILE" <<EOF
$BEGIN
if [ -z "\${WAYLAND_DISPLAY:-}" ] && [ "\${XDG_VTNR:-}" = 1 ]; then
  exec start-hyprland
fi
$END
EOF

echo ":: экран блокировки при входе"
set_lock_on_start true

echo ":: отключаю SDDM (текущий сеанс не трогаю)"
sudo systemctl disable sddm

if pacman -Qq sddm >/dev/null 2>&1; then
  read -r -p "Удалить пакет sddm совсем? [y/N] " a
  if [ "$a" = y ] || [ "$a" = Y ]; then sudo pacman -R sddm; fi
fi

echo
echo "Готово. После перезагрузки вместо SDDM будет экран блокировки оболочки."
echo "Вернуть как было: $0 --undo"
