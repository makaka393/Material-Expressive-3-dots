"""Служба ассистента: unix-сокет $XDG_RUNTIME_DIR/glass-assistant.sock, JSON по строке.

Команды (клиент → служба):
  {"cmd": "ask", "text": "...", "speak": false}   вопрос текстом (лаунчер)
  {"cmd": "listen"}                              выслушать вопрос голосом и ответить голосом; второй раз — стоп
  {"cmd": "stop"}                                прервать: слушание, ответ, озвучку
  {"cmd": "say", "text": "..."}                  просто произнести
  {"cmd": "reset"}                               забыть разговор
  {"cmd": "status"}
События (служба → все клиенты):
  {"ev": "state", "state": "idle|listening|transcribing|thinking|speaking", "wake": bool}
  {"ev": "level", "v": 0…1}       громкость микрофона, пока слушает
  {"ev": "heard", "text": "..."}  что распознано
  {"ev": "delta", "text": "..."}  кусочек ответа
  {"ev": "done", "text": "...", "backend": "claude|local"}
  {"ev": "error", "text": "..."}
"""
import asyncio
import json
import os
import re
import signal
import time

from . import config
from .llm import Brain
from .stt import Mic, Vad, Whisper, record_utterance, FRAME, RATE
from .tts import Sentences, Voice


class Daemon:
    def __init__(self):
        self.brain = Brain()
        self.whisper = Whisper()
        self.voice = Voice()
        self.clients = set()
        self.state = "idle"
        self.job = None
        self.wake_task = None

    # ── события
    async def emit(self, ev, **kw):
        line = (json.dumps({"ev": ev, **kw}, ensure_ascii=False) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(line)
            except (ConnectionError, RuntimeError):
                self.clients.discard(w)

    async def set_state(self, s):
        self.state = s
        await self.emit("state", state=s, wake=bool(config.load()["wake"]), key=config.has_key())

    # ── задачи
    def start(self, coro):
        if self.job and not self.job.done():
            self.job.cancel()
        self.job = asyncio.create_task(self._run(coro))

    async def _run(self, coro):
        try:
            await coro
        except asyncio.CancelledError:
            self.voice.stop()
            raise
        except Exception as e:
            print("ошибка:", repr(e), flush=True)
            await self.emit("error", text=str(e) or type(e).__name__)
        finally:
            if asyncio.current_task() is self.job:
                await self.set_state("idle")

    def busy(self):
        return self.job is not None and not self.job.done()

    async def listen(self, cfg):
        await self.set_state("listening")
        warm = asyncio.create_task(self.whisper.ensure(cfg))      # Whisper грузится, пока ты говоришь
        audio = await record_utterance(cfg["mic"], lambda v: self.emit("level", v=round(v, 3)))
        if audio is None:
            warm.cancel()
            return
        await self.set_state("transcribing")
        await warm
        text = await self.whisper.transcribe(cfg, audio)
        await self.emit("heard", text=text)
        if text:
            await self.ask(text, voice=True)

    async def ask(self, text, voice=False, speak=None):
        cfg = config.load()
        speak = (cfg["speak_voice"] if voice else cfg["speak_typed"]) if speak is None else speak
        await self.set_state("thinking")
        cut = Sentences()
        spoke = False
        if speak:
            asyncio.create_task(self.voice.ready(cfg))             # Silero грузится, пока думает модель

        async def delta(chunk):
            nonlocal spoke
            await self.emit("delta", text=chunk)
            if speak:
                for s in cut.feed(chunk):
                    if not spoke:
                        spoke = True
                        await self.set_state("speaking")
                    await self.voice.say(s, cfg)

        full, backend = await self.brain.answer(text, voice=voice or speak, on_delta=delta)
        if speak:
            for s in cut.flush():
                if not spoke:
                    spoke = True
                    await self.set_state("speaking")
                await self.voice.say(s, cfg)
        await self.emit("done", text=full, backend=backend)
        if speak:
            await self.voice.idle.wait()

    # ── слово-активатор: короткие фразы распознаются Whisper; начинается с имени — это к нам
    async def wake_loop(self):
        while True:
            cfg = config.load()
            if not cfg["wake"]:
                await asyncio.sleep(2)
                continue
            if self.busy() or not self.voice.idle.is_set():
                await asyncio.sleep(0.3)
                continue
            try:
                await self._wake_once(cfg)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print("wake:", repr(e), flush=True)
                await asyncio.sleep(3)

    async def _wake_once(self, cfg):
        vad = Vad()
        chunks, talking_for, quiet, n = [], 0.0, 0.0, 0
        async with Mic(cfg["mic"]) as mic:
            async for frame in mic.frames():
                n += 1
                if self.busy() or not self.voice.idle.is_set() or not config.load()["wake"]:
                    return
                talking = vad.speech(vad.level(frame))
                if n < 10:
                    continue
                if talking or chunks:
                    chunks.append(frame)
                    talking_for += FRAME / RATE if talking else 0
                    quiet = 0.0 if talking else quiet + FRAME / RATE
                if chunks and (quiet > 0.6 or len(chunks) * FRAME / RATE > 6):
                    break
        if not chunks or talking_for < 0.3:
            return
        import numpy as np
        text = await self.whisper.transcribe(cfg, np.concatenate(chunks))
        rest = after_wake(text, cfg["wake_words"])
        if rest is None:
            return
        await self.emit("heard", text=text)
        if rest:
            self.start(self.ask(rest, voice=True))                # «Гласс, какая погода?» — сразу вопрос
        else:
            self.start(self.listen(cfg))                          # «Гласс!» — слушаем вопрос

    # ── обслуживание: выгрузить простаивающие модели
    async def reaper(self):
        while True:
            await asyncio.sleep(30)
            cfg = config.load()
            try:
                await self.whisper.reap(cfg, keep=cfg["wake"])
                await self.brain.local.reap(cfg)
            except Exception as e:
                print("reaper:", repr(e), flush=True)

    # ── клиенты
    async def client(self, reader, writer):
        self.clients.add(writer)
        await self.emit("state", state=self.state, wake=bool(config.load()["wake"]), key=config.has_key())
        try:
            while line := await reader.readline():
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                await self.command(msg)
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            self.clients.discard(writer)
            writer.close()

    async def command(self, msg):
        cmd = msg.get("cmd")
        cfg = config.load()
        if cmd == "ask" and msg.get("text", "").strip():
            self.voice.stop()
            self.start(self.ask(msg["text"].strip(), voice=False, speak=msg.get("speak")))
        elif cmd == "listen":
            if self.busy() or not self.voice.idle.is_set():
                await self.command({"cmd": "stop"})
            else:
                self.start(self.listen(cfg))
        elif cmd == "stop":
            self.voice.stop()
            if self.busy():
                self.job.cancel()
            await self.set_state("idle")
        elif cmd == "say" and msg.get("text"):
            await self.voice.say(msg["text"], cfg)
        elif cmd == "reset":
            self.brain.reset()
        elif cmd == "status":
            await self.emit("state", state=self.state, wake=bool(cfg["wake"]), key=config.has_key())

    async def serve(self):
        path = config.SOCKET
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        server = await asyncio.start_unix_server(self.client, path=str(path))
        os.chmod(path, 0o600)
        tasks = [asyncio.create_task(self.reaper()), asyncio.create_task(self.wake_loop())]
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stop.set)
        print(f"glass-assistant: {path}", flush=True)
        async with server:
            await stop.wait()
        for t in tasks:
            t.cancel()
        self.voice.stop()
        await self.whisper.stop()
        await self.brain.local.stop()
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def after_wake(text: str, words) -> str | None:
    """Если фраза начинается с имени ассистента — остаток фразы ("" — только имя), иначе None."""
    t = re.sub(r"[^\w\s-]", " ", text.lower()).split()
    if not t:
        return None
    for w in words:
        w = w.lower()
        for i in range(min(3, len(t))):              # «эй, гласс …», «окей гласс …»
            if t[i].startswith(w[:max(4, len(w) - 1)]):
                tail = text.split(None, i + 1)
                return tail[i + 1].strip(" ,.!?") if len(tail) > i + 1 else ""
    return None
