"""Локальный мозг: Gemma 4 E4B в llama-server — быстрые ответы и действия на компьютере.

Один проход модели: вызвала инструменты — выполняем и отвечаем их результатом, без второго
прохода (ради скорости). Системный промпт и список инструментов не меняются от вопроса к вопросу —
llama-server держит их в кэше, и каждый вопрос стоит только свои ~40 токенов.
"""
import asyncio
import json
import os
import re
import shutil
import time
from dataclasses import dataclass, field
from datetime import datetime

import httpx2

from . import config, intents, memory, tools

SYSTEM = """Ты — голосовой ассистент на компьютере пользователя (Arch Linux, Hyprland). Отвечай по-русски.
- Просят что-то сделать — вызови инструмент. Не переспрашивай, если можно разумно догадаться.
- Несколько действий в одной фразе — несколько вызовов.
- Подходящего инструмента нет — коротко скажи, что пока так не умеешь. Не вызывай другой инструмент вместо него.
- Вопрос или разговор — ответь сам, одно-два коротких предложения, без markdown. Не знаешь точно — ответь
  примерно и скажи, что это примерно.
В начале сообщения в квадратных скобках — дата и время, это справка, не слова пользователя."""

CANT_TEXT = "Пока так не умею."
DAYS = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
HISTORY_IDLE = 120               # с: разговор с локальной моделью короткий — «а теперь громче»
STAMP = re.compile(r"^\s*\[[^\]]*\]\s*")
# «Блокирую экран.» без вызова инструмента — модель только пообещала; переспрашиваем с обязательным вызовом
CLAIM = re.compile(r"^((хорошо|конечно|ладно|окей|ок|сейчас|с удовольствием),?\s*)?(я\s+)?(блокирую|заблокирую|"
                   r"включаю|включу|выключаю|выключу|отключаю|отключу|выполняю|перезагружаю|запускаю|запущу|"
                   r"начинаю|открываю|открою|ставлю|поставлю|делаю|сделаю|переключаю|переключу|меняю|сменю|"
                   r"убавляю|убавлю|прибавляю|прибавлю|вызываю|проверяю|запомнил|запоминаю|забыл|забываю)", re.I)
# вызов, написанный текстом: «power off», «suggest_claude{}», «media{"action": …» — тоже переспрашиваем.
# Ассистент отвечает по-русски, так что короткий текст из одной латиницы — не ответ
PSEUDO = re.compile(r"[\x20-\x7e]*[A-Za-z][\x20-\x7e]*")
# выход для переспроса: с обязательным вызовом и без него модель хватает любой инструмент
# (на «открой браузер» выключила «не беспокоить»)
NOTHING = {"type": "function", "function": {
    "name": "nothing_fits", "description": "Подходящего инструмента нет — ничего не делать",
    "parameters": {"type": "object", "properties": {}, "required": []}}}


MODES = (["-ngl", "99", "-fit", "off"], ["--fit", "on"], ["-ngl", "8", "-fit", "off"], ["-ngl", "0", "-fit", "off"])


@dataclass
class Reply:
    text: str
    actions: list = field(default_factory=list)     # [{"name", "args", "ok", "show", "say"}]


def system(cfg) -> str:
    """Имя — одной строкой в конце: «Ты — <имя>…» в начале промпта делало модель болтливой, она отвечала словами
    вместо вызовов (eval 63/78 и 0,75 с против 70/78 и 0,42 с). Имя и память меняются редко — кэш не сбивается."""
    return SYSTEM + f"\nТебя зовут {config.NAME}." + memory.store.prompt()


class LocalServer:
    """llama-server: грузится заранее (Super+A, слово-активатор, режим «?» лаунчера) и выгружается после
    простоя или при запуске игры — видеопамять нужна и им."""

    def __init__(self, port: int = 8091):
        self.port = port
        self.proc = None
        self.used = 0.0
        self.lock = asyncio.Lock()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.port}"

    async def ensure(self, cfg):
        async with self.lock:
            self.used = time.monotonic()
            if self.proc and self.proc.returncode is None:
                return
            exe = shutil.which("llama-server")
            if not exe or not os.path.exists(cfg["local_model"]):
                raise RuntimeError("локальная модель не установлена")
            # сначала целиком в видеопамять (втрое быстрее); не влезла (игра, Waydroid) — что влезет:
            # --fit on иногда падает (GGML_ASSERT), тогда 8 слоёв на видеокарте, а нет — только процессор
            for mode in MODES:
                if await self._start(exe, cfg, mode):
                    return
            raise RuntimeError("Локальная модель не запустилась (см. logs/llama-server.log)")

    async def _start(self, exe, cfg, mode) -> bool:
        log = open(config.DATA / "logs/llama-server.log", "ab")
        self.proc = await asyncio.create_subprocess_exec(
            exe, "-m", cfg["local_model"], "--host", "127.0.0.1", "--port", str(self.port),
            "-c", "8192", "-np", "1", "-fa", "auto", "--jinja", "--reasoning", "off", "--no-webui",
            *mode,
            stdout=log, stderr=log)
        async with httpx2.AsyncClient() as http:
            for _ in range(240):                          # до минуты: модель грузится с диска
                if self.proc.returncode is not None:
                    return False
                try:
                    if (await http.get(self.url + "/health", timeout=1)).status_code == 200:
                        return True
                except httpx2.HTTPError:
                    pass
                await asyncio.sleep(0.25)
        self.proc.terminate()
        await self.proc.wait()
        return False

    async def warm(self, cfg):
        try:
            await self.ensure(cfg)
        except Exception as e:
            print("локальная модель не прогрелась:", e, flush=True)

    async def unload(self):
        async with self.lock:
            if self.proc and self.proc.returncode is None:
                self.proc.terminate()
                await self.proc.wait()
            self.proc = None

    async def reap(self, cfg):
        if self.proc and self.proc.returncode is None and time.monotonic() - self.used > cfg["local_idle_min"] * 60:
            await self.unload()

    async def stop(self):
        await self.unload()


class Gate:
    """Фильтр текста ответа: срезает метку «[дата, время]», которую модель любит повторять, и
    придерживает начало, пока не ясно, не пустое ли это обещание («Блокирую экран.»)."""

    def __init__(self):
        self.buf = ""
        self.open = False
        self.claimed = False

    def feed(self, chunk: str) -> str:
        if self.open:
            return chunk
        if self.claimed:
            return ""
        self.buf += chunk
        head = self.buf.lstrip()
        if head.startswith("[") and "]" not in head and len(head) < 60:
            return ""                                   # метка ещё не кончилась
        head = STAMP.sub("", self.buf)
        if len(head) < 20 and not CLAIM.match(head):
            return ""                                   # мало текста, чтобы понять
        return self._decide(head)

    def flush(self) -> str:
        if self.open or self.claimed:
            return ""
        return self._decide(STAMP.sub("", self.buf))

    def _decide(self, head: str) -> str:
        if CLAIM.match(head) or (len(head.strip()) <= 60 and PSEUDO.fullmatch(head.strip())):
            self.claimed = True
            return ""
        self.open = True
        return head


class LocalBrain:
    def __init__(self, server: LocalServer):
        self.server = server
        self.history = []        # реплики: [user, assistant, tool…] — списки сообщений OpenAI
        self.last = 0.0

    def reset(self):
        self.history = []

    @staticmethod
    def stamp(text: str) -> str:
        now = datetime.now()
        return f"[{now:%Y-%m-%d %H:%M}, {DAYS[now.weekday()]}]\n{text}"

    async def answer(self, text, voice, on_delta, on_action) -> Reply:
        cfg = config.load()
        if self.history and time.monotonic() - self.last > HISTORY_IDLE:
            self.history = []
        about = intents.about(text)
        if about:                                # «как тебя зовут» — без модели (intents.about)
            await on_delta(about)
            self.history = (self.history + [[{"role": "user", "content": self.stamp(text)},
                                             {"role": "assistant", "content": about}]])[-cfg["local_history_turns"]:]
            self.last = time.monotonic()
            return Reply(about, [])
        fast = intents.match(text)
        if fast:                                 # частая команда — без модели (и даже без её загрузки)
            return await self._fast(text, *fast, cfg, on_action)
        await self.server.ensure(cfg)
        # спрошено голосом или нет — запрос тот же: указание «ответ озвучат» сбивает модель, и вместо
        # вызова инструмента она пишет «Устанавливаю громкость…»; ответы и так короткие, числа словами
        # делает озвучка (numbers.py)
        user = {"role": "user", "content": self.stamp(text)}
        msgs = [{"role": "system", "content": system(cfg)}, *[m for turn in self.history for m in turn], user]

        gate = Gate()
        shown = []

        async def on_text(chunk):
            out = gate.feed(chunk)
            if out:
                shown.append(out)
                await on_delta(out)

        content, calls = await self._complete(msgs, on_text)
        rest = gate.flush()
        if rest:
            shown.append(rest)
            await on_delta(rest)
        if not calls and (gate.claimed or not "".join(shown).strip()):
            # пообещала, написала вызов текстом или промолчала — переспросить; «подходящего нет» — честно сказать
            _, calls = await self._complete(msgs, None, tool_choice="required", extra=[NOTHING])
            if not calls or any(c["name"] == NOTHING["function"]["name"] for c in calls):
                calls = []
                shown = [CANT_TEXT]
                await on_delta(CANT_TEXT)

        actions, results, read = [], [], False
        for i, c in enumerate(calls):
            c["id"] = c["id"] or f"call_{i}"
            res = await tools.run(c["name"], c["arguments"])
            try:
                args = json.loads(c["arguments"] or "{}")
            except ValueError:
                args = {}
            action = {"name": c["name"], "args": args, "ok": res.ok, "show": res.show, "say": res.say}
            actions.append(action)
            results.append(res.data or res.show or ("ок" if res.ok else "ошибка"))
            await on_action(action)
            read = read or bool(res.data)

        if read:                                 # нашла в интернете — второй проход: ответ по выдаче
            said = await self._read_results(msgs, calls, results, shown, on_delta)
            shown.append(said)
            results = [r[:1500] for r in results]      # в историю — покороче: кэш и следующие вопросы

        reply_text = "".join(shown)
        turn = [user, {"role": "assistant", "content": "".join(shown) or None,
                       **({"tool_calls": [{"id": c["id"], "type": "function",
                                           "function": {"name": c["name"], "arguments": c["arguments"]}}
                                          for c in calls]} if calls else {})}]
        turn += [{"role": "tool", "tool_call_id": c["id"], "content": r} for c, r in zip(calls, results)]
        self.history = (self.history + [turn])[-cfg["local_history_turns"]:]
        self.last = time.monotonic()
        return Reply(reply_text, actions)

    async def _read_results(self, msgs, calls, results, shown, on_delta) -> str:
        """Ответ по результатам инструментов (поиск): вызовы и их выдача — в разговор, модель пишет текст."""
        follow = msgs + [{"role": "assistant", "content": "".join(shown) or None,
                          "tool_calls": [{"id": c["id"], "type": "function",
                                          "function": {"name": c["name"], "arguments": c["arguments"]}} for c in calls]}]
        follow += [{"role": "tool", "tool_call_id": c["id"], "content": r} for c, r in zip(calls, results)]
        parts = []

        async def out(chunk):
            parts.append(chunk)
            await on_delta(chunk)
        await self._complete(follow, out, tool_choice="none")
        return "".join(parts)

    async def _fast(self, text, name, args, cfg, on_action) -> Reply:
        res = await tools.run(name, args)
        action = {"name": name, "args": args, "ok": res.ok, "show": res.show, "say": res.say}
        await on_action(action)
        # в историю — как будто модель сама вызвала: «а ещё чуть-чуть» она поймёт
        call = {"id": "fast_0", "type": "function", "function": {"name": name, "arguments": json.dumps(args, ensure_ascii=False)}}
        turn = [{"role": "user", "content": self.stamp(text)}, {"role": "assistant", "content": None, "tool_calls": [call]},
                {"role": "tool", "tool_call_id": "fast_0", "content": res.show or ("ок" if res.ok else "ошибка")}]
        self.history = (self.history + [turn])[-cfg["local_history_turns"]:]
        self.last = time.monotonic()
        return Reply("", [action])

    async def _complete(self, msgs, on_text, tool_choice=None, extra=()):
        """Потоковый запрос; текст — в on_text по кускам, вызовы собираются из кусков. → (текст, вызовы)."""
        body = {"messages": msgs, "tools": tools.openai_tools() + list(extra), "stream": True, "temperature": 0.2,
                "max_tokens": 600, "cache_prompt": True}
        if tool_choice:
            body["tool_choice"] = tool_choice
        parts, calls = [], {}
        async with httpx2.AsyncClient(timeout=httpx2.Timeout(120.0, connect=3.0)) as http:
            async with http.stream("POST", self.server.url + "/v1/chat/completions", json=body) as r:
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if not line.startswith("data: ") or line == "data: [DONE]":
                        continue
                    try:
                        delta = json.loads(line[6:])["choices"][0]["delta"]
                    except (ValueError, KeyError, IndexError):
                        continue
                    for tc in delta.get("tool_calls") or []:
                        c = calls.setdefault(tc.get("index", 0), {"id": "", "name": "", "arguments": ""})
                        c["id"] = tc.get("id") or c["id"]
                        f = tc.get("function") or {}
                        c["name"] += f.get("name") or ""
                        c["arguments"] += f.get("arguments") or ""
                    if delta.get("content"):
                        parts.append(delta["content"])
                        if on_text:
                            await on_text(delta["content"])
        return "".join(parts), [calls[i] for i in sorted(calls)]
