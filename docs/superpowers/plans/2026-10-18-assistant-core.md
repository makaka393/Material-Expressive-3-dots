# Ядро ассистента (этап 1) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** локальная Gemma 4 E4B отвечает и выполняет действия по умолчанию; «морковка» в начале фразы отправляет её в Claude.

**Architecture:** чистый `router.route()` выбирает мозг; `LocalBrain` (llama-server) и `ClaudeBrain` (Anthropic SDK) вызывают общий реестр `tools`; демон шлёт события `action`/`delta`/`done` в сокет, оболочка их показывает.

**Tech Stack:** Python 3.14 (asyncio, httpx2, anthropic 1.15), llama-server b9789, Quickshell QML, Hyprland.

**Spec:** `docs/superpowers/specs/2026-10-18-assistant-core-design.md`

## Global Constraints

- Тесты — `unittest` из стандартной библиотеки, запуск: `cd assistant && ~/.local/share/glass-assistant/venv/bin/python -m unittest discover -s tests -v`.
- Без новых pip-зависимостей. Команды — без shell (`asyncio.create_subprocess_exec`).
- Комментарии и строки — по-русски, в стиле существующего кода (короткие, «зачем», не «что»).
- llama-server: `-ngl 99 -fit off -c 8192 -np 1 -fa auto --jinja --reasoning off --no-webui`, порт 8091; запасной запуск — те же флаги с `--fit on` вместо `-ngl 99 -fit off`.
- Модель: `~/.local/share/glass-assistant/models/llm/gemma-4-E4B-it-Q4_K_M.gguf`.
- Ключи конфига: `claude_words: ["морковка"]`, `local_idle_min: 30`, `local_history_turns: 6`; `backend`: `auto` | `claude` | `local`.
- Протокол сокета только дополняется: старые команды и события не меняются.
- Живую оболочку не подменять: QML проверять копией на временном headless-мониторе (см. память «Shell testing»); при выкладке — сначала новые файлы, потом `shell.qml`.

## Review Focus

1. «Морковка» с заглавной, запятой, «!» или огрехом распознавания («морковку», «Морковка!») — всё равно Claude. → тест в Task 1.
2. Вопрос пришёл, пока модель ещё грузится (Super+A уже вызвал `warm`) — один процесс llama-server, вопрос ждёт загрузки. → тест в Task 4.
3. Два действия в одной фразе, первое упало — второе выполняется, оба в ответе. → тест в Task 4.
4. Модель прислала аргументы строками (`"level": "40"`) или битый JSON — приведение или понятная ошибка, без падения. → тест в Task 2.
5. «Морковка» одна, без прошлого вопроса, текстом — ошибка «Что спросить у Claude?», без падения. → тест в Task 6.

---

### Task 1: Маршрутизатор

**Files:**
- Create: `assistant/glass_assistant/router.py`
- Test: `assistant/tests/test_router.py` (+ пустой `assistant/tests/__init__.py`)

**Interfaces:**
- Produces: `Route(brain: str, text: str, escalated: bool)` (dataclass, `brain` ∈ `"local"|"claude"`); `route(text: str, cfg: dict, to: str | None = None, last: str | None = None) -> Route`; `strip_word(text: str, words: list[str]) -> str | None` (остаток после слова или `None`, если слова нет — тот же алгоритм, что `after_wake` в `daemon.py`; `after_wake` переписать через него).

- [ ] **Step 1: Write the failing tests**

```python
CFG = {"backend": "auto", "claude_words": ["морковка"]}
def test_plain_goes_local(self): self.assertEqual(route("следующий трек", CFG), Route("local", "следующий трек", False))
def test_word_goes_claude(self): self.assertEqual(route("Морковка, почему небо синее?", CFG), Route("claude", "почему небо синее?", False))
def test_word_forms(self):  # падежи и огрехи распознавания
    for t in ("морковку, что такое кварк", "морковка! что такое кварк", "эй морковка что такое кварк"):
        self.assertEqual(route(t, CFG).brain, "claude")
def test_word_later_in_phrase_ignored(self): self.assertEqual(route("купи морковку и лук пожалуйста", CFG).brain, "local")
def test_word_alone_escalates_last(self): self.assertEqual(route("морковка", CFG, last="как работает ядро"), Route("claude", "как работает ядро", True))
def test_word_alone_no_last(self): self.assertEqual(route("Морковка.", CFG), Route("claude", "", True))
def test_to_claude(self): self.assertEqual(route("привет", CFG, to="claude").brain, "claude")
def test_backend_claude(self): self.assertEqual(route("привет", {**CFG, "backend": "claude"}).brain, "claude")
def test_backend_local_ignores_word(self): self.assertEqual(route("морковка, привет", {**CFG, "backend": "local"}), Route("local", "морковка, привет", False))
```

«купи морковку…» — слово на первом месте только после служебных («эй», «окей») или само первое; правило: искать в первых трёх словах, но слова до него — только из `{"эй", "окей", "ок", "слушай"}` или имя активатора. Иначе бытовая фраза с «морковкой» уйдёт в Claude.

- [ ] **Step 2: Run, expect FAIL** (`ModuleNotFoundError: glass_assistant.router`)
- [ ] **Step 3: Implement `router.py`** — `route` без ввода-вывода; `to="claude"` / `backend="claude"` → Claude с исходным текстом (слово, если есть, срезается).
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `assistant: маршрутизатор — «морковка» отправляет фразу в Claude`

### Task 2: Реестр инструментов

**Files:**
- Create: `assistant/glass_assistant/tools/__init__.py`, `assistant/glass_assistant/tools/base.py`
- Test: `assistant/tests/test_tools.py`

**Interfaces:**
- Produces:
  - `base.Result(ok: bool, show: str, say: str | None = None)` (dataclass);
  - `base.Tool(name: str, description: str, params: dict, required: list[str], handler: Callable[[dict], Awaitable[Result]], claude: bool = True)`;
  - `async base.sh(*argv: str, timeout: float = 5) -> str` — stdout, `RuntimeError` при ненулевом коде или таймауте;
  - `async base.qs(target: str, fn: str, *args) -> str` — `sh("qs", "ipc", "-c", "glass", "call", target, fn, *map(str, args))`;
  - `tools.register(tool: Tool)`, `tools.TOOLS: dict[str, Tool]`, `tools.openai_tools() -> list[dict]`, `tools.anthropic_tools() -> list[dict]` (без `claude=False`), `async tools.run(name: str, args: dict | str) -> Result`;
  - `tools.SUGGEST = "suggest_claude"` — инструмент без обработчика действия: `run` возвращает `Result(True, "", None)`, смысл ему придаёт `LocalBrain`.

- [ ] **Step 1: Write the failing tests** (регистрировать тестовые инструменты во временном реестре — `TOOLS` подменять через `unittest.mock.patch.dict`)

```python
async def test_unknown_tool(self): r = await tools.run("nope", {}); self.assertFalse(r.ok); self.assertIn("nope", r.show)
async def test_coerces_numbers(self):   # Review Focus 4
    # инструмент с params {"level": {"type": "integer"}} получает {"level": "40"} → обработчик видит 40
async def test_bad_json_args(self): r = await tools.run("echo", "{level: 4"); self.assertFalse(r.ok)
async def test_unexpected_arg_dropped(self): # {"level": 1, "zzz": 2} → обработчик видит только level
async def test_handler_exception(self): # обработчик бросает RuntimeError("нет плеера") → Result(False, "Не получилось: нет плеера")
async def test_handler_timeout(self):   # обработчик спит 6 с → Result(False, …) не позже чем через 5.5 с
def test_schemas(self):
    # openai_tools()[i] == {"type": "function", "function": {"name", "description", "parameters": {"type": "object", "properties", "required"}}}
    # anthropic_tools()[i] == {"name", "description", "input_schema": {...}}; suggest_claude там нет
```

- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement** `base.py` и `tools/__init__.py`; `run` берёт `json.loads`, если `args` — строка; приведение: `integer` из строки цифр, `boolean` из `"true"/"false"`; таймаут — `asyncio.wait_for(…, 5)`.
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `assistant: реестр инструментов — общие схемы для локальной модели и Claude`

### Task 3: Инструменты этапа 1 + IPC оболочки

**Files:**
- Create: `assistant/glass_assistant/tools/media.py` (`media`), `assistant/glass_assistant/tools/system.py` (`volume`, `brightness`, `night_light`, `do_not_disturb`, `suggest_claude`)
- Modify: `config/quickshell/glass/Brightness.qml` (добавить `IpcHandler { target: "brightness"; function set(v: int): int; function change(d: int): int }` — оба вызывают `root.set()` и возвращают `root.value`), `config/quickshell/glass/Notifs.qml` (в `IpcHandler` `notifs` добавить `function set(on: bool): void { Config.dnd = on; }`)
- Test: `assistant/tests/test_tools_stage1.py`

**Interfaces:**
- Consumes: `base.sh`, `base.qs`, `tools.register` (Task 2).
- Produces: инструменты в `tools.TOOLS` с именами и параметрами ровно как в `bench.py` спайка (описания взять оттуда же, версия v2: `media` — «Управление тем, что уже играет: пауза, продолжить («включи музыку» без названия — play), следующий/предыдущий трек («следующую», «скип»), перемотка»; без `like`). `suggest_claude` — описание: «Вопрос сложный: нужны свежие данные из интернета, точные факты, код или долгие рассуждения. Вызови вместо ответа». `tools/__init__.py` импортирует `media` и `system` в конце, чтобы они зарегистрировались.

- [ ] **Step 1: Write the failing tests** — подменить `base.sh`/`base.qs` записывающей заглушкой (`patch("glass_assistant.tools.base.sh")` и т.п.), проверять argv и `Result`:

```python
("media", {"action": "toggle"})               → sh("playerctl", "play-pause"); ok, show «Пауза/продолжить», say None
("media", {"action": "next"})                 → sh("playerctl", "next"); show «Следующий трек»
("media", {"action": "seek_forward", "seconds": 30}) → sh("playerctl", "position", "30+")
("media", {"action": "seek_back"})            → sh("playerctl", "position", "10-")   # по умолчанию 10 с
("volume", {"change": 10})                    → sh("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "10%+"), затем get-volume; заглушка отдаёт "Volume: 0.40" → show «Громкость 40%»
("volume", {"level": 30})                     → "30%"
("volume", {"mute": True})                    → sh("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"); show «Звук выключен»
("brightness", {"change": -20})               → qs("brightness", "change", -20); заглушка "60" → show «Яркость 60%»
("night_light", {"on": True})                 → qs("night", "enable")
("do_not_disturb", {"on": False})             → qs("notifs", "set", "false")
("media", {"action": "next"}) когда sh бросает RuntimeError("No players found") → ok False, show «Не получилось: плеер не запущен»
```

- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement** обработчики и правки QML.
- [ ] **Step 4: Run, expect PASS.** Затем на живой системе: `qs ipc -c glass call brightness change 0` печатает текущее значение (проверить, что Quickshell отдаёт возврат функции в stdout; если нет — `change` пишет значение в `/run/user/1000/glass-brightness` и инструмент читает файл).
- [ ] **Step 5: Commit** `assistant: инструменты — плеер, громкость, яркость, ночной режим, «не беспокоить»`

### Task 4: Локальный мозг

**Files:**
- Create: `assistant/glass_assistant/local.py`
- Modify: `assistant/glass_assistant/config.py` (ключи из Global Constraints, `local_model` → Gemma)
- Test: `assistant/tests/test_local.py`

**Interfaces:**
- Consumes: `tools.openai_tools`, `tools.run`, `tools.SUGGEST`, `Result` (Task 2–3).
- Produces:
  - `LocalServer(port: int = 8091)`: `async ensure(cfg) -> None`, `async warm(cfg) -> None` (= `ensure` в фоне, ошибки только в лог), `async unload() -> None`, `async reap(cfg) -> None`, `url: str`, `async stop()`;
  - `Reply(text: str, actions: list[dict], suggest: bool)`; `actions[i] = {"name", "args", "ok", "show"}`;
  - `LocalBrain(server: LocalServer)`: `async answer(text: str, voice: bool, on_delta: Callable[[str], Awaitable], on_action: Callable[[dict], Awaitable]) -> Reply`, `reset()`.
- Системный промпт — `SYSTEM` из `bench.py` спайка (дословно) + `VOICE_NOTE` из нынешнего `llm.py`, если `voice`.

- [ ] **Step 1: Write the failing tests** — поддельный llama-server: `asyncio.start_server` на свободном порту, отдаёт `/health` 200 и на `/v1/chat/completions` заранее заданные SSE-ответы; запоминает тела запросов.

```python
async def test_streams_text_and_strips_stamp(self):  # SSE: "[2026-10-18 14:05, воскресенье] ", "Привет", "!" → on_delta получил "Привет!" ; reply.text == "Привет!"
async def test_tool_call_from_chunks(self):        # tool_calls кусками: name "volume", arguments '{"cha' + 'nge": 10}' → tools.run("volume", {"change": 10}) один раз; on_action вызван; второго запроса к модели нет
async def test_claim_without_call_retries(self):    # 1-й ответ — текст "Блокирую экран.", 2-й (tool_choice=="required" в теле) — вызов lock… (тестовый инструмент) → выполнен; текст "Блокирую экран." не попал в on_delta
async def test_two_actions_one_fails(self):         # Review Focus 3: два вызова, первый Result(False,…) → оба в reply.actions, второй выполнен
async def test_suggest(self):                       # вызов suggest_claude → reply.suggest is True, reply.text == "Это лучше спросить у Claude — скажи «морковка»."
async def test_history_kept_and_trimmed(self):      # 7 вопросов подряд → в 8-м запросе 6 прошлых реплик; через 121 с (подменить time.monotonic) — пусто
async def test_concurrent_ensure_one_process(self): # Review Focus 2: warm() и answer() одновременно → create_subprocess_exec вызван один раз (patch)
async def test_fallback_to_fit_on(self):            # первый процесс сразу выходит с кодом 1 → второй запуск с "--fit", "on"
```

Буферизация метки: пока накопленный текст начинается с `[` и нет `]` (и меньше 40 символов) — не отдавать в `on_delta`; затем срезать `^\s*\[[^\]]*\]\s*`. Слова-«обещания» для повтора: `^(хорошо,?\s*)?(блокирую|включаю|выключаю|выполняю|перезагружаю|запускаю|открываю|ставлю|делаю|переключаю|убавляю|прибавляю)` — проверять, прежде чем отдать первый кусок текста в `on_delta` (буфер до первых ~20 символов).

- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement `local.py`**, правки `config.py`.
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `assistant: локальный мозг — Gemma 4 E4B с инструментами`

### Task 5: Claude с инструментами

**Files:**
- Create: `assistant/glass_assistant/claude.py` (перенос `Conversation`, `SYSTEM`, `VOICE_NOTE`, `echo_blocks`, `MissingKey`, `_ask_claude` из `llm.py`)
- Delete: `assistant/glass_assistant/llm.py`
- Test: `assistant/tests/test_claude.py`

**Interfaces:**
- Consumes: `tools.anthropic_tools`, `tools.run` (Task 2).
- Produces: `ClaudeBrain()`: `async answer(text: str, voice: bool, on_delta, on_action) -> Reply` (тот же `Reply` из `local.py`; `suggest` всегда `False`), `reset()`; исключения недоступности — как сейчас (`MissingKey`, `anthropic.APIConnectionError` и т.д.) летят наружу, ловит демон. `UNAVAILABLE: tuple[type[Exception], ...]` — список этих исключений для демона.

Перед кодом: загрузить скилл `claude-api` (правило проекта для кода с Anthropic SDK) и сверить с ним поток с инструментами для `anthropic` 1.15 (`beta.messages.stream` с `tools=`, `stop_reason == "tool_use"`, блоки `tool_result`).

- [ ] **Step 1: Write the failing tests** — подменённый клиент (`ClaudeBrain._claude` возвращает фейк, чей `beta.messages.stream(...)` — асинхронный контекст-менеджер с `text_stream` и `get_final_message()`):

```python
async def test_text_answer(self):     # один круг, stop_reason "end_turn" → reply.text, on_delta по кускам
async def test_tool_round(self):      # 1-й круг: блок tool_use(id="t1", name="volume", input={"change": 10}), stop_reason "tool_use"
                                      # → tools.run вызван; 2-й запрос содержит assistant-блоки 1-го круга и user [{"type":"tool_result","tool_use_id":"t1","content":"Громкость 50%"}]; 2-й круг — текст
async def test_tool_rounds_capped(self):  # модель всё время просит инструмент → не больше 5 кругов, затем ответ «Не получилось закончить» 
async def test_missing_key(self):     # без ANTHROPIC_API_KEY → MissingKey
async def test_tools_passed(self):    # tools= в запросе == anthropic_tools(); suggest_claude среди них нет
```

- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement `claude.py`, удалить `llm.py`**
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `assistant: Claude получает те же инструменты; llm.py разнесён`

### Task 6: Демон

**Files:**
- Modify: `assistant/glass_assistant/daemon.py`, `assistant/glass_assistant/__main__.py` (команды `claude "вопрос"`, `warm`, `unload`; печать событий `action` как `⚙ <show>`)
- Test: `assistant/tests/test_daemon.py`

**Interfaces:**
- Consumes: `route`, `strip_word` (Task 1); `LocalServer`, `LocalBrain`, `Reply` (Task 4); `ClaudeBrain`, `UNAVAILABLE` (Task 5).
- Produces: команды сокета `ask{text, speak, to}`, `listen{to}`, `warm`, `unload`; события `action{name,args,ok,show}`, `done{text, backend, actions}`.

Поведение `ask`:
1. `r = route(text, cfg, to, last=self.last_local если ему < 120 с)`;
2. `r.brain == "claude"` и `r.text == ""`: голос → `listen(to="claude")`; текст → `error` «Что спросить у Claude?»;
3. Claude бросил исключение из `UNAVAILABLE` → `delta` «Claude недоступен — отвечаю сама: » и ответ `LocalBrain`;
   локальная не поднялась (`RuntimeError` из `LocalServer.ensure`) и есть ключ → `delta` «Локальная модель не запустилась — спросил Claude: » и ответ Claude; ключа нет → `error` с текстом исключения (тест `test_local_down_uses_claude`);
4. ответ локальной: запомнить `last_local = (r.text, time)`; `reply.suggest` → то же, плюс ответ-подсказка;
5. озвучка: текст ответа по предложениям, как сейчас; если ответ — только действия, говорить `say` результатов (у большинства `None` — тишина);
6. `done.text` — текст ответа или `show` действий через « · ».

`listen` и слово-активатор вызывают `self.local.warm(cfg)` в начале; `warm`/`unload` — команды сокета; `reaper` выгружает и локальную модель.

- [ ] **Step 1: Write the failing tests** — `Daemon` с подменёнными `local_brain`/`claude_brain`/`voice`/`whisper` (заглушки), клиент — список событий через подменённый `emit`:

```python
async def test_plain_to_local(self)          # ask "следующий трек" → local_brain.answer вызван; done.backend == "local"
async def test_word_to_claude(self)          # ask "морковка, что такое кварк" → claude_brain.answer("что такое кварк", …)
async def test_word_alone_escalates(self)    # ask "как работает ядро" (local) → ask "морковка" → claude получил "как работает ядро"
async def test_word_alone_nothing_typed(self) # Review Focus 5: ask "морковка" без прошлого → событие error "Что спросить у Claude?"; Claude не вызван
async def test_claude_unavailable(self)      # claude бросает MissingKey → local вызван; первая delta начинается с "Claude недоступен"
async def test_actions_in_done(self)         # local вернул Reply("", [{"name":"media","show":"Следующий трек",…}], False) → done.text == "Следующий трек", done.actions длины 1
async def test_listen_warms(self)            # listen → local_server.warm вызван до записи
```

- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run all tests, expect PASS**
- [ ] **Step 5: Commit** `assistant: демон — маршрут, события действий, прогрев и выгрузка модели`

### Task 7: Оболочка и клавиши

**Files:**
- Modify: `config/quickshell/glass/Assistant.qml`, `LauncherContent.qml`, `DynamicIsland.qml`, `SettingsContent.qml`, `config/hypr/hyprland.lua`, `config/hypr/hyprland.conf`, `config/hypr/scripts/gamemode-start.sh`

**Interfaces:**
- Consumes: протокол сокета Task 6.
- Produces: `Assistant.listenClaude()`, `Assistant.askClaude(text)`, `Assistant.warm()`, `Assistant.unload()`, `Assistant.actions: var` (массив `{name, ok, show}` текущего ответа); те же четыре функции в `IpcHandler "assistant"`; `cfg.claudeWords`.

- [ ] **Step 1:** `Assistant.qml` — функции, обработка `action` (сброс `actions` при новом вопросе), `done.actions`.
- [ ] **Step 2:** `LauncherContent.qml` — текст `?` с ведущим `?` (то есть «??…») → `Assistant.askClaude(текст без ?)`; вход в режим «?» → `Assistant.warm()`; подпись «Gemma 4» вместо «Qwen3.5»; при ответе-действиях — строки `show` с иконкой `bolt` (ошибка — `error`).
- [ ] **Step 3:** `DynamicIsland.qml` — пустой `answer` и есть `actions` → показывать их `show` через « · ».
- [ ] **Step 4:** `SettingsContent.qml` — подписи вариантов `backend`: `auto` «Локально, Claude по слову», `claude` «Всегда Claude», `local` «Только локально»; строка «Слово для Claude: «<claudeWords[0]>»».
- [ ] **Step 5:** клавиши: `SUPER + SHIFT + A` → `qs ipc -c glass call assistant listenClaude` в `hyprland.lua` (рядом с Super+A, тот же стиль комментария) и `hyprland.conf`; в `gamemode-start.sh` — `qs ipc -c glass call assistant unload` (без ошибки, если оболочки нет: `|| true`).
- [ ] **Step 6: Проверка** — копия оболочки на headless-мониторе «glasstest» (процедура из памяти «Shell testing»): в логе Quickshell нет ошибок загрузки; через IPC копии `assistant askClaude`/`ask` карточка лаунчера и острова показывает действия и подпись. Скриншот копии.
- [ ] **Step 7: Commit** `glass: ассистент — Claude по Super+Shift+A и «??», карточки действий, выгрузка модели в игре`

### Task 8: Установка, оценка, выкладка

**Files:**
- Modify: `assistant/setup.sh` (Gemma вместо Qwen3.5-9B, убрать `--no-local`, шапка), `README.md` (раздел ассистента: локально по умолчанию, «морковка», Super+Shift+A, «??»)
- Create: `assistant/tests/eval_local.py` (фразы спайка для инструментов этапа 1 + разговорные + ловушки «как выключить компьютер в линуксе»; печатает счёт, медиану и максимум времени; не входит в `unittest discover` — имя без `test_`)

- [ ] **Step 1:** правки `setup.sh`, README.
- [ ] **Step 2:** `eval_local.py` на живой модели (поднимает свой llama-server на 8093). Ожидание: ≥ 95 % верно, медиана < 0,5 с. Хуже — править описания инструментов, повторять.
- [ ] **Step 3:** выкладка: `./assistant/setup.sh` (докачает только недостающее; Gemma уже лежит), QML — в `~/.config/quickshell/glass` (сначала новые файлы, потом `touch shell.qml`), `hyprctl reload`.
- [ ] **Step 4: Живая проверка** — `python -m glass_assistant ask "сделай громче"` → громкость выросла, затем «сделай тише» → вернулась; «включи ночной режим» / «выключи ночной режим»; `python -m glass_assistant ask "морковка, привет"` → без ключа «Claude недоступен — отвечаю сама: …». `journalctl --user -u glass-assistant` без ошибок.
- [ ] **Step 5: Commit** `assistant: установка с Gemma 4, оценка на живой модели, README`
