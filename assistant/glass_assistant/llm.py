"""Мозг ассистента: Claude по API, запасной — локальная модель через llama-server.

Разговор помнится, пока идёт (до history_turns реплик или history_idle_min минут тишины), потом
начинается заново. История только дописывается в конец: у Claude Opus 5.5 блоки размышлений
привязаны к разговору, и правка ранних реплик их ломает — поэтому старое не обрезается.
"""
import asyncio
import json
import os
import shutil
import subprocess
import time
from datetime import datetime

import anthropic
import httpx2

from . import config

SYSTEM = """Ты — личный ассистент в оболочке glass на компьютере пользователя (Arch Linux, Hyprland, \
Quickshell). Тебя вызывают голосом или из лаунчера (Super+Space, затем «?»).

Как отвечать:
- На языке пользователя (обычно русский), по-дружески и по делу, без канцелярита.
- Коротко: сначала сам ответ, детали — только если просили или без них никак.
- Не выдумывай. Если не знаешь или не уверен — так и скажи.
- В начале сообщения пользователя в квадратных скобках — текущие дата, время и город; \
это справка от оболочки, не слова пользователя."""

VOICE_NOTE = ("Этот ответ будет озвучен голосом. Одно-три коротких предложения, без markdown, списков, "
              "эмодзи и ссылок. Числа, даты и единицы пиши словами, как произносишь.")


class Conversation:
    """Реплики разговора. Для Claude хранятся блоки ответа как есть (с размышлениями), для локальной
    модели — только текст."""

    def __init__(self):
        self.turns = []          # [{"user": str, "voice": bool, "blocks": list | None, "text": str}]
        self.last = 0.0

    def stale(self, cfg) -> bool:
        return (len(self.turns) >= cfg["history_turns"]
                or (self.turns and time.monotonic() - self.last > cfg["history_idle_min"] * 60))

    def claude_messages(self, user_text: str) -> list:
        msgs = []
        for t in self.turns:
            msgs.append({"role": "user", "content": t["user"]})
            # указание «ответ будет озвучен» остаётся в истории там же, где было: размышления Claude
            # привязаны к тому, что было перед ними, и правка прошлого их ломает
            if t["voice"]:
                msgs.append({"role": "system", "content": VOICE_NOTE})
            msgs.append({"role": "assistant", "content": t["blocks"] if t["blocks"] else t["text"]})
        msgs.append({"role": "user", "content": user_text})
        return msgs

    def local_messages(self, user_text: str, voice: bool) -> list:
        msgs = [{"role": "system", "content": SYSTEM + ("\n\n" + VOICE_NOTE if voice else "")}]
        for t in self.turns:
            msgs.append({"role": "user", "content": t["user"]})
            msgs.append({"role": "assistant", "content": t["text"]})
        msgs.append({"role": "user", "content": user_text})
        return msgs

    def add(self, user_text, voice, blocks, text):
        self.turns.append({"user": user_text, "voice": voice, "blocks": blocks, "text": text})
        self.last = time.monotonic()


class LocalServer:
    """llama-server по требованию: запускается при первом запросе, выгружается после простоя.
    Слои, которые не влезают в видеопамять (там ещё рабочий стол и Whisper), --fit оставит в ОЗУ."""

    PORT = 8091

    def __init__(self):
        self.proc = None
        self.used = 0.0
        self.lock = asyncio.Lock()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.PORT}"

    async def ensure(self, cfg):
        async with self.lock:
            self.used = time.monotonic()
            if self.proc and self.proc.returncode is None:
                return
            exe = shutil.which("llama-server")
            if not exe or not os.path.exists(cfg["local_model"]):
                raise RuntimeError("локальная модель не установлена")
            log = open(config.DATA / "logs/llama-server.log", "ab")
            self.proc = await asyncio.create_subprocess_exec(
                exe, "-m", cfg["local_model"], "--host", "127.0.0.1", "--port", str(self.PORT),
                "-c", "8192", "-fa", "auto", "--no-webui",
                # без размышлений: запасной модели нужна скорость, а не глубина
                "--reasoning-budget", "0", "--chat-template-kwargs", '{"enable_thinking": false}',
                stdout=log, stderr=log)
            async with httpx2.AsyncClient() as http:
                for _ in range(240):                          # до минуты: модель грузится с диска
                    if self.proc.returncode is not None:
                        raise RuntimeError("llama-server не запустился (см. logs/llama-server.log)")
                    try:
                        if (await http.get(self.url + "/health", timeout=1)).status_code == 200:
                            return
                    except httpx2.HTTPError:
                        pass
                    await asyncio.sleep(0.25)
            raise RuntimeError("llama-server не ответил за минуту")

    async def reap(self, cfg):
        if self.proc and self.proc.returncode is None and time.monotonic() - self.used > cfg["local_idle_min"] * 60:
            self.proc.terminate()
            await self.proc.wait()
            self.proc = None

    async def stop(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
            await self.proc.wait()


class Brain:
    def __init__(self):
        self.conv = Conversation()
        self.local = LocalServer()
        self.client = None

    def _claude(self):
        if self.client is None:
            self.client = anthropic.AsyncAnthropic(max_retries=1, timeout=anthropic.Timeout(60.0, connect=4.0))
        return self.client

    @staticmethod
    def stamp(text: str) -> str:
        now = datetime.now().astimezone()
        return f"[{now:%Y-%m-%d %H:%M}, {now:%A}]\n{text}"

    async def answer(self, text: str, voice: bool, on_delta):
        """Ответ по кусочкам (on_delta(str)); возвращает (весь текст, кто ответил)."""
        cfg = config.load()
        if self.conv.stale(cfg):
            self.conv = Conversation()
        user = self.stamp(text)
        backend = cfg["backend"]
        if backend in ("auto", "claude"):
            try:
                return await self._ask_claude(cfg, user, voice, on_delta), "claude"
            except (anthropic.AuthenticationError, anthropic.PermissionDeniedError, anthropic.APIConnectionError,
                    anthropic.APITimeoutError, anthropic.RateLimitError, anthropic.InternalServerError, MissingKey) as e:
                if backend == "claude":
                    raise
                print(f"claude недоступен ({type(e).__name__}), отвечает локальная модель", flush=True)
        return await self._ask_local(cfg, user, voice, on_delta), "local"

    async def _ask_claude(self, cfg, user, voice, on_delta) -> str:
        if not config.has_key():
            raise MissingKey()
        messages = self.conv.claude_messages(user)
        if voice:
            # указание для этого ответа — системным сообщением в конце: кэш промпта и истории не сбивается
            messages.append({"role": "system", "content": VOICE_NOTE})
        parts = []
        async with self._claude().beta.messages.stream(
            model=cfg["model"],
            max_tokens=4096,
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            output_config={"effort": cfg["effort"]},
            cache_control={"type": "ephemeral"},
            system=SYSTEM,
            messages=messages,
        ) as stream:
            async for chunk in stream.text_stream:
                parts.append(chunk)
                await on_delta(chunk)
            final = await stream.get_final_message()
        text = "".join(parts)
        if final.stop_reason == "refusal":
            text = text or "Тут я помочь не могу."
            if not parts:
                await on_delta(text)
            self.conv.add(user, voice, None, text)   # отказ не продолжаем блоками — только текстом
            return text
        self.conv.add(user, voice, echo_blocks(final.content), text)
        return text

    async def _ask_local(self, cfg, user, voice, on_delta) -> str:
        await self.local.ensure(cfg)
        body = {"messages": self.conv.local_messages(user, voice), "stream": True,
                "temperature": 0.6, "max_tokens": 1024}
        parts = []
        async with httpx2.AsyncClient(timeout=httpx2.Timeout(120.0, connect=3.0)) as http:
            async with http.stream("POST", self.local.url + "/v1/chat/completions", json=body) as r:
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if not line.startswith("data: ") or line == "data: [DONE]":
                        continue
                    try:
                        delta = json.loads(line[6:])["choices"][0]["delta"].get("content") or ""
                    except (ValueError, KeyError, IndexError):
                        continue
                    if delta:
                        parts.append(delta)
                        await on_delta(delta)
        self.local.used = time.monotonic()
        text = "".join(parts)
        self.conv.add(user, voice, None, text)
        return text

    def reset(self):
        self.conv = Conversation()


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
    """Нет ключа Claude API — сразу к локальной модели."""
