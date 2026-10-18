"""Служба ассистента: unix-сокет $XDG_RUNTIME_DIR/glass-assistant.sock, JSON по строке.

Куда идёт вопрос — решает router.route(): по умолчанию локальная модель (local.py), «морковь, …» в
начале фразы — Claude (claude.py).

Команды (клиент → служба):
  {"cmd": "ask", "text": "...", "speak": false, "to": "claude"}   вопрос текстом (лаунчер); to — сразу в Claude
  {"cmd": "listen", "to": "claude"}              выслушать вопрос голосом и ответить голосом; второй раз — стоп
  {"cmd": "warm"} | {"cmd": "unload"}            загрузить локальную модель заранее | выгрузить (игра)
  {"cmd": "stop"}                                прервать: слушание, ответ, озвучку
  {"cmd": "say", "text": "..."}                  просто произнести
  {"cmd": "reset"}                               забыть разговор
  {"cmd": "status"}
События (служба → все клиенты):
  {"ev": "state", "state": "idle|listening|transcribing|thinking|speaking", "wake": bool}
  {"ev": "level", "v": 0…1}       громкость микрофона, пока слушает
  {"ev": "heard", "text": "..."}  что распознано
  {"ev": "route", "brain": "local|claude", "text": "..."}   кто отвечает и на что (без «морковь»)
  {"ev": "delta", "text": "..."}  кусочек ответа
  {"ev": "action", "name": "...", "args": {...}, "ok": true, "show": "Следующий трек"}   выполнено действие
  {"ev": "done", "text": "...", "backend": "claude|local", "actions": [...]}
  {"ev": "error", "text": "..."}
"""
import asyncio
import json
import os
import re
import signal
import time


import httpx2

from . import chime, config
from .claude import UNAVAILABLE, ClaudeBrain
from .local import LocalBrain, LocalServer
from .router import route, wake
from .tools import base, power, timers
from .stt import Mic, Vad, Whisper, record_utterance, FRAME, RATE
from .tts import Sentences, Voice


# диалог: после голосового ответа ещё раз слушаем без слова-активатора
FOLLOW_WAIT = 6          # с — ждём, заговорит ли
FOLLOW_MAX = 5           # реплик подряд; дальше — снова «обсидиан»
END = {"стоп", "хватит", "всё", "все", "отбой", "отмена", "пока", "спасибо", "спасибо всё", "спасибо все",
       "всё спасибо", "все спасибо", "спасибо хватит", "нет спасибо", "ничего"}
# что Whisper «слышит» в тишине, шуме и музыке
NOISE = ("продолжение следует", "субтитры", "спасибо за просмотр", "редактор субтитров", "подписывайтесь",
         "музыка", "аплодисменты", "смех", "dimatorzok")


def _plain(text: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", " ", text.lower()).split())


class Daemon:
    def __init__(self):
        self.local = LocalServer()
        self.local_brain = LocalBrain(self.local)
        self.claude_brain = ClaudeBrain()
        self.last_local = None           # (вопрос, время): «морковь» без вопроса переспросит его у Claude
        self.stopping = asyncio.Event()  # SIGTERM/SIGINT
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

    async def listen(self, cfg, to=None, depth=0):
        """depth > 0 — продолжение разговора: ждём недолго, шум и «хватит» его заканчивают."""
        await self.set_state("listening")
        warm = asyncio.create_task(self.whisper.ensure(cfg))      # Whisper грузится, пока ты говоришь
        if to != "claude" and cfg["backend"] != "claude":
            asyncio.create_task(self.local.warm(cfg))             # и локальная модель
        level = lambda v: self.emit("level", v=round(v, 3))
        pause = float(cfg.get("pause") or 2.0)
        audio = await (record_utterance(cfg["mic"], level, max_wait=FOLLOW_WAIT, tail=pause) if depth
                       else record_utterance(cfg["mic"], level, tail=pause))
        if audio is None:
            warm.cancel()
            return
        await self.set_state("transcribing")
        await warm
        text = await self.whisper.transcribe(cfg, audio)
        plain = _plain(text or "")
        if depth and (len(plain) < 2 or plain.startswith(NOISE)):
            return                                                # тишина или музыка — разговор окончен
        await self.emit("heard", text=text)
        if depth and plain in END:
            chime.play("done")
            return
        if text:
            await self.ask(text, voice=True, to=to, depth=depth)

    async def ask(self, text, voice=False, speak=None, to=None, depth=0):
        cfg = config.load()
        speak = (cfg["speak_voice"] if voice else cfg["speak_typed"]) if speak is None else speak
        if power.pending():                                      # «Выключить компьютер?» — «да»
            answer = await power.confirm(text)
            if answer is not None:
                await self.emit("route", brain="local", text=text)
                await self.emit("done", text=answer.show, backend="local", actions=[])
                if speak:
                    await self.voice.say(answer.say, cfg)
                    await self.voice.idle.wait()
                return
        last = self.last_local[0] if self.last_local and time.monotonic() - self.last_local[1] < 120 else None
        r = route(text, cfg, to=to, last=last)
        if r.brain == "claude" and not r.text:
            if voice:
                await self.listen(cfg, to="claude")                # «морковь» — и слушаем вопрос
            else:
                await self.emit("error", text="Что спросить у Claude?")
            return
        await self.emit("route", brain=r.brain, text=r.text)
        await self.set_state("thinking")
        cut = Sentences()
        said, actions = [], []
        spoke = False
        if speak:
            asyncio.create_task(self.voice.ready(cfg))             # Silero грузится, пока думает модель

        async def speak_text(s):
            nonlocal spoke
            if not spoke:
                spoke = True
                await self.set_state("speaking")
            await self.voice.say(s, cfg)

        async def delta(chunk):
            said.append(chunk)
            await self.emit("delta", text=chunk)
            if speak:
                for s in cut.feed(chunk):
                    await speak_text(s)

        async def action(a):
            actions.append(a)
            await self.emit("action", name=a["name"], args=a["args"], ok=a["ok"], show=a["show"])

        v = voice or speak
        backend = r.brain
        if r.brain == "claude":
            try:
                await self.claude_brain.answer(r.text, v, delta, action)
            except UNAVAILABLE as e:
                print(f"claude недоступен ({type(e).__name__}), отвечает локальная модель", flush=True)
                await delta("Claude недоступен — отвечаю " + ("сама" if config.female(cfg) else "сам") + ": ")
                await self.local_brain.answer(r.text, v, delta, action)
                backend = "local"
        else:
            try:
                await self.local_brain.answer(r.text, v, delta, action)
            except (RuntimeError, httpx2.HTTPError) as e:
                if not config.has_key():
                    raise
                print(f"локальная модель: {e!r}, отвечает Claude", flush=True)
                await delta("Локальная модель не запустилась — спросил Claude: ")
                await self.claude_brain.answer(r.text, v, delta, action)
                backend = "claude"
            self.last_local = (r.text, time.monotonic())
        if speak:
            for s in cut.flush():
                await speak_text(s)
            if not "".join(said).strip():
                # ответ — только действия: смену трека и так слышно, а ошибку надо сказать
                for a in actions:
                    s = a["say"] or (None if a["ok"] else a["show"])
                    if s:
                        await speak_text(s)
        text = "".join(said).strip() or " · ".join(a["show"] for a in actions if a["show"])
        await self.emit("done", text=text, backend=backend,
                        actions=[{k: a[k] for k in ("name", "args", "ok", "show")} for a in actions])
        if speak:
            await self.voice.idle.wait()
            # вопрос о питании ждёт ответа — слушаем его, даже если «разговор» выключен
            if voice and (cfg.get("follow_up") and depth < FOLLOW_MAX or power.pending()):
                # диалог: слушаем ответ без слова-активатора; начали с Claude — с ним и продолжаем
                await self.listen(cfg, to="claude" if backend == "claude" else None, depth=depth + 1)

    async def announce(self, text, kind):
        """Напоминание или будильник: тост в острове, звук, голос."""
        await base.qs("island", "toast", "alarm", "Будильник" if kind == "alarm" else "Напоминание", text)
        chime.play("alarm" if kind == "alarm" else "wake")
        await self.voice.say(("Напоминаю: " + text) if kind == "reminder" else text, config.load())

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
                # «Обсидиан… выкрути яркость» с паузой — одна фраза; длинной команде — до 12 с
                if chunks and (quiet > float(cfg.get("pause") or 2.0) or len(chunks) * FRAME / RATE > 12):
                    break
        if not chunks or talking_for < 0.2:                  # «Обс» — короче полсекунды
            return
        import numpy as np
        await self.on_wake(await self.whisper.transcribe(cfg, np.concatenate(chunks)), cfg)

    async def on_wake(self, text, cfg):
        rest = after_wake(text, config.wake_words(cfg))
        if rest is None:
            return
        await self.emit("heard", text=text)
        if cfg["backend"] != "claude":
            asyncio.create_task(self.local.warm(cfg))
        if rest:
            self.start(self.ask(rest, voice=True))                # «Ирис, какая погода?» — сразу вопрос
        else:
            chime.play("wake")                                    # «Ирис!» — звук и слушаем вопрос
            self.start(self.listen(cfg))

    # ── обслуживание: выгрузить простаивающие модели
    async def reaper(self):
        while True:
            await asyncio.sleep(30)
            cfg = config.load()
            try:
                await self.whisper.reap(cfg, keep=cfg["wake"])
                await self.local.reap(cfg)
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
            self.start(self.ask(msg["text"].strip(), voice=False, speak=msg.get("speak"), to=msg.get("to")))
        elif cmd == "listen":
            if self.busy() or not self.voice.idle.is_set():
                await self.command({"cmd": "stop"})
            else:
                self.start(self.listen(cfg, to=msg.get("to")))
        elif cmd == "warm":
            asyncio.create_task(self.local.warm(cfg))
        elif cmd == "unload":
            await self.local.unload()
        elif cmd == "stop":
            self.voice.stop()
            if self.busy():
                self.job.cancel()
            await self.set_state("idle")
        elif cmd == "say" and msg.get("text"):
            # «прослушать» в настройках присылает голос сам — файл настроек мог ещё не записаться
            over = {k: msg[m] for k, m in (("voice", "voice"), ("voice_pitch", "pitch"), ("voice_rate", "rate")) if msg.get(m)}
            await self.voice.say(msg["text"], {**cfg, **over})
        elif cmd == "reset":
            self.local_brain.reset()
            self.claude_brain.reset()
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
        timers.SCHED = timers.Scheduler(config.DATA / "reminders.json", self.announce)
        tasks = [asyncio.create_task(self.reaper()), asyncio.create_task(self.wake_loop()),
                 asyncio.create_task(timers.SCHED.run()),
                 asyncio.create_task(self.voice.ready(config.load()))]       # голос — заранее, не при первом ответе
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self.stopping.set)
        print(f"glass-assistant: {path}", flush=True)
        async with server:
            await self.stopping.wait()
            for t in tasks:
                t.cancel()
            # выход из async with ждёт, пока закроются все подключения, а оболочка держит своё всегда —
            # без этого служба висела до SIGKILL от systemd
            for w in list(self.clients):
                w.close()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.remove_signal_handler(sig)
        self.voice.stop()
        await self.whisper.stop()
        await self.local.stop()
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def after_wake(text: str, words) -> str | None:
    """Если фраза начинается с имени ассистента — остаток фразы ("" — только имя), иначе None."""
    return wake(text, words)                    # «эй, Ирис …», «Iris, …» — по звучанию
