# glass-dots

Arch + Hyprland в стиле **Material 3 Expressive + матовое стекло**. Все цвета — из обоев
через [matugen](https://github.com/InioX/matugen) и меняются на лету.

![рабочий стол](assets/desktop-182723.png)

## Что внутри

- **Бар на Quickshell** — рабочие столы, запущенные приложения, часы, погода, плеер в стиле Google,
  раскладка, громкость (с выбором устройства вывода), меню питания, «динамический остров».
- **Выбор обоев и темы** — картинки, GIF и видео (mpvpaper); под обоями — кружки цветов, найденных
  на обоях: выбираешь, от какого цвета строить тему (как «Обои и стиль» на Pixel).
- **Тема везде**: Hyprland, kitty, rofi, btop, GTK, Dolphin/Qt (цветовая схема KDE + папки Papirus в цвет).
- **Скриншоты** — выделение со скруглёнными углами и свечение по краям экрана в стиле Gemini.
- **Покрути мышкой по кругу** → по краям вырастают чёрные рамки → выделяешь область → она уходит в Google Lens.
- **Экран входа SDDM** — часы, дата, погода, те же обои (и видео) и цвета, пароль рисуется
  фигурами Material 3 Expressive.


## Оболочка glass

- **Экран блокировки** — обои рабочего стола (видео тоже), часы, погода; пароль рисуется фигурами
  Material 3, как на Pixel. `Super+Esc`, кнопка в шторке, после AOD и перед сном.
  Вместо SDDM: `./lockscreen-instead-of-sddm.sh` (вернуть — `--undo`).
- **Always On Display** — семь циферблатов (формы, стрелки, орбита, точки, планеты, горизонт, сегменты),
  окна на это время гаснут.
- **Остров** — часы (клик — календарь), погода (клик — прогноз), плеер, уведомления, таймер
  (`timer 5m чай` в лаунчере), эквалайзер по настоящему звуку (cava).
- **Бар** — рабочие столы, док с подписями, системный трей, раскладка, громкость, шторка с нагрузкой
  на процессор, память и видеокарту; защита глаз умеет включаться сама от заката до рассвета.
- **Лаунчер** — приложения, открытые окна, калькулятор, эмодзи, пипетка, команды оболочки.
- **Шпаргалка по клавишам** — `Super+/`, читается прямо из `hyprland.conf`.
- **«Игра найдена!»** — нашлась катка в Dota 2, а ты на другом столе, в AOD или отошёл: приходит
  важное уведомление со звуком (даже в «Не беспокоить»), AOD гаснет. Проверить: `qs ipc -c glass call attention test`.
- **Стекло** — матовое, с сильным блюром (сила — в настройках), или тональные поверхности Material.

## Установка

```bash
git clone https://github.com/makaka393/glass-dots ~/glass-dots
cd ~/glass-dots && ./install.sh
```

Установщик ставит пакеты (pacman + yay/paru для AUR), раскладывает конфиги в `~/.config`
(старые — в `~/.config-backup-<дата>`), ставит тему SDDM и применяет первую тему.
Обои клади в папку из `config/quickshell/glass/Theme.qml` (`wallpaperDir`).

Город для погоды — `lat`/`lon` в `Theme.qml`.

## Горячие клавиши

```
bind = $mainMod, SPACE, exec, rofi -show drun
bind = SUPER SHIFT, S, exec, ~/.config/hypr/scripts/screenshot.sh region
bind = $mainMod, W, exec, qs ipc -c glass call picker toggle
bind = SUPER SHIFT, A, exec, ~/.config/hypr/scripts/screenshot.sh pretty
bind = , Print, exec, ~/.config/hypr/scripts/screenshot.sh full
bind = SUPER SHIFT, G, exec, ~/.config/hypr/scripts/screenshot.sh lens
```

## Настройки

| что | где |
|---|---|
| схема / контраст / тёмная-светлая | `~/.config/hypr/scripts/theme.env` |
| сменить обои из терминала | `changetheme.sh <файл> [#цвет]` |
| жест «покрути мышкой» | начало `~/.config/hypr/scripts/shake-lens.py` (CIRCLES, START, NO_FULLSCREEN) |
| толщина чёрных рамок жеста | `~/.config/quickshell/glow/shell.qml` (`shell.shake * N`) |

## Спасибо

- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — идеи и дизайн (illogical impulse)
- [end-4/rounded-polygon-qmljs](https://github.com/end-4/rounded-polygon-qmljs) — фигуры Material 3 (Apache-2.0, `sddm/glass/shapes`)
- [3d3f/ii-sddm-theme](https://github.com/3d3f/ii-sddm-theme) — идея пароля фигурами
- [matugen](https://github.com/InioX/matugen), [Quickshell](https://quickshell.org)
