"""Claude по API — для сложных вопросов: «морковка, …», Super+Shift+A, «??» в лаунчере.

Разговор помнится, пока идёт (до history_turns вопросов или history_idle_min минут тишины), потом
начинается заново. История только дописывается в конец: у Claude Opus 5.5 блоки размышлений
привязаны к разговору, и правка ранних реплик их ломает — поэтому старое не обрезается.
"""
import time
from datetime import datetime

import anthropic

from . import config, tools
from .local import Reply

SYSTEM = """Ты — личный ассистент в оболочке glass на компьютере пользователя (Arch Linux, Hyprland, \
Quickshell). Обычно отвечает локальная модель, а тебя зовут для сложных вопросов: словом «морковка», \
клавишами Super+Shift+A или «??» в лаунчере.

Как отвечать:
- На языке пользователя (обычно русский), по-дружески и по делу, без канцелярита.
- Коротко: сначала сам ответ, детали — только если просили или без них никак.
- Не выдумывай. Если не знаешь или не уверен — так и скажи.
- Просят что-то сделать на компьютере — используй инструменты.
- В начале сообщения пользователя в квадратных скобках — текущие дата и время; \
это справка от оболочки, не слова пользователя."""

VOICE_NOTE = ("Этот ответ будет озвучен голосом. Одно-три коротких предложения, без markdown, списков, "
              "эмодзи и ссылок. Числа, даты и единицы пиши словами, как произносишь.")

MAX_ROUNDS = 5               # кругов «инструмент → результат» на один вопрос


class Conversation:
    """Сообщения разговора как есть (с блоками размышлений и вызовами инструментов), только дописываются."""

    def __init__(self):
        self.messages = []
        self.questions = 0
        self.last = 0.0

    def stale(self, cfg) -> bool:
        return (self.questions >= cfg["history_turns"]
                or (self.messages and time.monotonic() - self.last > cfg["history_idle_min"] * 60))


class ClaudeBrain:
    def __init__(self):
        self.conv = Conversation()
        self.client = None

    def _claude(self):
        if self.client is None:
            self.client = anthropic.AsyncAnthropic(max_retries=1, timeout=anthropic.Timeout(60.0, connect=4.0))
        return self.client

    def reset(self):
        self.conv = Conversation()

    @staticmethod
    def stamp(text: str) -> str:
        now = datetime.now().astimezone()
        return f"[{now:%Y-%m-%d %H:%M}, {now:%A}]\n{text}"

    async def answer(self, text, voice, on_delta, on_action) -> Reply:
        cfg = config.load()
        if self.conv.stale(cfg):
            self.conv = Conversation()
        if not config.has_key():
            raise MissingKey()
        msgs = self.conv.messages
        start = len(msgs)
        msgs.append({"role": "user", "content": self.stamp(text)})
        if voice:
            # указание — системным сообщением после вопроса: кэш промпта и истории не сбивается
            msgs.append({"role": "system", "content": VOICE_NOTE})
        try:
            reply = await self._rounds(cfg, msgs, on_delta, on_action)
        except BaseException:
            del msgs[start:]                 # неудачный вопрос не остаётся в истории
            raise
        self.conv.questions += 1
        self.conv.last = time.monotonic()
        return reply

    async def _rounds(self, cfg, msgs, on_delta, on_action) -> Reply:
        parts, actions = [], []

        async def say(chunk):
            parts.append(chunk)
            await on_delta(chunk)

        for _ in range(MAX_ROUNDS):
            if parts and not parts[-1][-1:].isspace():
                await say(" ")               # текст до инструмента и после — через пробел
            fresh = len(parts)
            async with self._claude().beta.messages.stream(
                model=cfg["model"],
                max_tokens=16000,
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                output_config={"effort": cfg["effort"]},
                cache_control={"type": "ephemeral"},
                system=SYSTEM,
                tools=tools.anthropic_tools(),
                messages=msgs,
            ) as stream:
                async for chunk in stream.text_stream:
                    await say(chunk)
                final = await stream.get_final_message()
            if final.stop_reason == "refusal":
                if len(parts) == fresh:
                    await say("Тут я помочь не могу.")
                msgs.append({"role": "assistant", "content": "".join(parts[fresh:])})   # отказ — только текстом
                return Reply("".join(parts).strip(), actions)
            msgs.append({"role": "assistant", "content": echo_blocks(final.content)})
            if final.stop_reason != "tool_use":
                return Reply("".join(parts).strip(), actions)
            results = []
            for b in final.content:
                if b.type != "tool_use":
                    continue
                res = await tools.run(b.name, b.input)
                action = {"name": b.name, "args": b.input, "ok": res.ok, "show": res.show, "say": res.say}
                actions.append(action)
                await on_action(action)
                result = {"type": "tool_result", "tool_use_id": b.id, "content": res.show or ("ок" if res.ok else "ошибка")}
                if not res.ok:
                    result["is_error"] = True
                results.append(result)
            msgs.append({"role": "user", "content": results})
        await say("Не получилось закончить.")
        return Reply("".join(parts).strip(), actions)


def echo_blocks(content):
    """Блоки ответа для истории. Если на этой реплике сработала запасная модель (блок fallback),
    до последнего такого блока возвращаем только текст — размышления и вызовы инструментов
    отказавшей модели обратно не отправляют."""
    cut = max((i for i, b in enumerate(content) if b.type == "fallback"), default=-1)
    if cut < 0:
        return content
    keep = {"thinking", "redacted_thinking", "tool_use", "server_tool_use"}
    return [b for i, b in enumerate(content) if i > cut or b.type not in keep]


class MissingKey(Exception):
    """Нет ключа Claude API."""


# Claude недоступен — демон отвечает локальной моделью с пометкой
UNAVAILABLE = (anthropic.AuthenticationError, anthropic.PermissionDeniedError, anthropic.APIConnectionError,
               anthropic.APITimeoutError, anthropic.RateLimitError, anthropic.InternalServerError, MissingKey)
