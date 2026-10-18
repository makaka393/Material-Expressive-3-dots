# Навыки ассистента (этап 2–3) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** «обсидиан» + полный набор действий на компьютере голосом + анимация-орб.

**Architecture:** новые модули `tools/*.py` регистрируются в общем реестре (этап 1); служба получает
планировщик напоминаний и подтверждение питания; оболочка — слой `AssistantOrb.qml`.

**Tech Stack:** Python 3.14 asyncio (без новых зависимостей), Hyprland 0.56 Lua-диспетчеры через
`hyprctl dispatch '<lua>'`, Quickshell QML.

**Spec:** `docs/superpowers/specs/2026-10-18-assistant-skills-design.md`

## Global Constraints

- Тесты: `cd assistant && ~/.local/share/glass-assistant/venv/bin/python -m unittest discover -s tests`.
- Внешние команды — только через `base.sh` / `base.qs` / `base.hypr` (их подменяют тесты); без shell.
- Каждый инструмент возвращает `Result(ok, show, say)`; `say` — только там, где ответ надо услышать
  (справка, подтверждение, ошибка).
- Диспетчеры Hyprland — Lua: `hl.dsp.focus({ window = "address:0x…" })`, `hl.dsp.focus({ workspace = N })`,
  `hl.dsp.window.close({ window = … })`, `hl.dsp.window.move({ workspace = N, window = … })`,
  `hl.dsp.window.fullscreen()`, `hl.dsp.window.float({ action = "toggle" })`, `hl.dsp.window.pin()`.
- Живую оболочку проверять копией на headless-мониторе (память «Shell testing»).

## Review Focus

1. «Открой телегу», когда Telegram уже открыт на другом рабочем столе — показать его, а не второй экземпляр. → Task 2.
2. «Да» через 30 с после вопроса о выключении — ничего не выключать. → Task 7.
3. Служба перезапустилась с напоминанием на завтра — напоминание сработает. → Task 6.
4. Модель вызвала `close_app` для приложения без окон — понятный ответ, не падение. → Task 2.
5. Голосовое «обсидиан» без вопроса — звук и слушание, а не ответ на пустоту. → Task 1.

---

### Task 1: Слово-активатор — «Obsidian», кавычки, звук

**Files:** `router.py`, `config.py`, `daemon.py`, новый `chime.py`; тесты `test_router.py`, `test_daemon.py`.
**Produces:** `chime.play(kind: str = "wake") -> None` (не блокирует; `pw-play` из `$XDG_RUNTIME_DIR/glass-chime-<kind>.wav`, файл создаётся один раз numpy-синусом).

- [ ] Тесты: `strip_word("«Обсидиан, морковь, почему?»", ["обсидиан"]) == "морковь, почему?"`; `route` по «Obsidian, …» с дефолтами; после слова-активатора без вопроса демон вызывает `chime.play("wake")` и `listen`.
- [ ] RED → код → GREEN → commit `assistant: «Obsidian» и кавычки в слове-активаторе, звук «слушаю»`.

### Task 2: Приложения и сайты

**Files:** `tools/apps.py`, `tools/base.py` (`hypr(lua) -> str`, `clients() -> list[dict]`); тест `test_tools_apps.py`.
**Produces:** `apps.find(name) -> Entry | None` (`Entry(id, name, wm_class, exec)`), инструменты `open_app`, `close_app`, `open_url`, `web_search`.

- [ ] Тесты (каталог .desktop во временной папке через `apps.DIRS`): точное имя, русское имя, прозвище («телега» → org.telegram.desktop), Keywords, «браузер» → default browser; уже открыт → `hypr('hl.dsp.focus({ window = "address:0x1" })')`, не `gtk-launch`; не найдено → `ok=False`; `close_app` без окон → `ok=False, show="Окна «…» нет"`; `web_search(site="youtube")` → `xdg-open https://www.youtube.com/results?search_query=…`.
- [ ] RED → код → GREEN → commit.

### Task 3: Окна и рабочие столы

**Files:** `tools/windows.py`; тест `test_tools_windows.py`. Инструменты `window(action, app?)`, `move_window(workspace, app?)`, `workspace(number)`.

- [ ] Тесты на точные Lua-строки для каждого действия; с `app` — адрес окна из `clients()`.
- [ ] RED → код → GREEN → commit.

### Task 4: Оболочка — скриншот, запись, блокировка, обои

**Files:** `tools/shell.py`; тест `test_tools_shell.py`. Обои — из `wallpaper_dir` (по умолчанию читается из `Theme.qml`, свойство `wallpaperDir`), расширения jpg/jpeg/png/webp/gif/mp4/webm/mkv/mov, выбор `random.choice` кроме текущего.

- [ ] Тесты argv; обои — временная папка; пустая папка → `ok=False`.
- [ ] RED → код → GREEN → commit.

### Task 5: Справка

**Files:** `tools/info.py`; тест `test_tools_info.py`. `system_info(kind)`; `kind` ∈ time, date, weather, cpu, gpu, memory, disk, headphones, now_playing. Чтение файлов и сеть — через подменяемые функции модуля (`read`, `fetch_json`).

- [ ] Тесты: каждый kind на подставных данных → текст `say` (числа цифрами — озвучка сама скажет словами).
- [ ] RED → код → GREEN → commit.

### Task 6: Таймеры, напоминания, будильник

**Files:** `tools/timers.py`, `daemon.py` (запуск планировщика, `announce`); тест `test_tools_timers.py`.
**Produces:** `timers.Scheduler(path, announce)`: `add(when: float, text: str, kind: str)`, `async run()`, `load()`; `base.announce` — колбэк службы `async (text, kind) -> None` (тост `island toast`, звук, голос).

- [ ] Тесты: `timer` → `qs("timer", "start", 5400, "…")`; `reminder(in_minutes=20)` → запись в файл с временем now+1200; срабатывание вызывает `announce`; перезапуск (новый Scheduler на том же файле) видит запись (Review Focus 3); просроченные при старте — срабатывают сразу с пометкой «пропущено»; `alarm("7:30")` в 8:00 → завтра.
- [ ] RED → код → GREEN → commit.

### Task 7: Питание с подтверждением

**Files:** `tools/power.py`, `daemon.py`; тест `test_tools_power.py`, `test_daemon.py`.
**Produces:** `power.pending() -> str | None`, `power.confirm(text) -> Result | None` (None — это не ответ на вопрос).

- [ ] Тесты: `power(shutdown)` ничего не запускает, `say` — вопрос; «да» в течение 20 с → `sh("systemctl", "poweroff")`; «нет» → «Отменил»; «да» через 30 с → не трогать (Review Focus 2); голосом — служба слушает ответ без слова-активатора.
- [ ] RED → код → GREEN → commit.

### Task 8: Музыка по названию

**Files:** `tools/media.py` (`play_music`); тест `test_tools_music.py`. Ключи — `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` из окружения; токен client credentials кэшируется до истечения.

- [ ] Тесты: с ключами → POST токена, GET `/v1/search?q=…&type=track&limit=1` (kind → type) → `sh("playerctl", "-p", "spotify", "open", "spotify:track:…")`; без ключей → `xdg-open spotify:search:<q>` и `say` про ключ; Spotify не запущен → сначала `gtk-launch spotify`.
- [ ] RED → код → GREEN → commit.

### Task 9: Промпт и оценка

**Files:** `local.py` (SYSTEM: что умеет; прозвища приложений не нужны — их знает `open_app`), `tests/eval_local.py` (+ фразы на все новые инструменты, ловушки).

- [ ] eval текстом и голосом ≥ 95 %, медиана < 0,5 с; хуже — править описания инструментов.
- [ ] commit.

### Task 10: Уровень озвучки и орб

**Files:** `tts.py` (огибающая предложения → `on_level` 20 раз/с во время проигрывания), `daemon.py`; оболочка: `AssistantOrb.qml` (новый), `shell.qml` (подключить), `Assistant.qml` (уровень и в `speaking`).

- [ ] Тест: `Voice` с подменённым проигрыванием вызывает `on_level` с убывающими/растущими значениями огибающей.
- [ ] Орб по спеку; проверка копией на headless-мониторе, скриншоты всех состояний через поддельную службу.
- [ ] commit.

### Task 11: Выкладка и живая проверка

- [ ] `wakeWords` в `~/.config/glass/assistant.json` + «obsidian»; rsync службы, QML (новые файлы сначала, потом `shell.qml`), перезапуск.
- [ ] Живьём: открыть/закрыть приложение (например, mpv/калькулятор — что-то безвредное), погода, время, таймер на 5 с, напоминание через 1 мин.
- [ ] README; commit.
