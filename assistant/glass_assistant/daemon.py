"""Служба ассистента: unix-сокет $XDG_RUNTIME_DIR/glass-assistant.sock, JSON по строке.

Куда идёт вопрос — решает router.route(): по умолчанию локальная модель (local.py), «морковь, …» в
начале фразы — Claude (claude.py).

Команды (клиент → служба):
  {"cmd": "ask", "text": "...", "speak": false, "to": "claude"}   вопрос текстом (лаунчер); to — сразу в Claude
  {"cmd": "listen", "to": "claude"}              выслушать вопрос голосом и ответить голосом; второй раз — стоп
  {"cmd": "warm"} | {"cmd": "unload"}            загрузить локальную модель заранее | выгрузить (игра)
  {"cmd": "stop"}                                прервать: слушание, ответ, озвучку
  {"cmd": "say", "text": "...", "preview": true, "voice": "baya", "tone": 0.5, "speed": 1.1, "height": 0}
                                                 произнести; preview — оборвать прошлое и этим голосом
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
import collections
import json
import os
import re
import signal
import time


import httpx2
import numpy as np

from . import chime, config
from .claude import UNAVAILABLE, ClaudeBrain
from .local import LocalBrain, LocalServer
from .router import route, sound, wake
from .tools import base, power, timers
from .stt import Mic, Vad, Whisper, record_utterance, FRAME, RATE
from .tts import Sentences, Voice


# диалог: после голосового ответа ещё раз слушаем без слова-активатора
FOLLOW_WAIT = 6          # с — ждём, заговорит ли
FOLLOW_MAX = 5           # реплик подряд; дальше — снова по имени
# слово-активатор: речь режется на кусочки по короткой тишине — имя проверяется сразу, а вопрос после него
# дослушивается до «паузы в конце фразы» из настроек
WAKE_GAP = 0.7           # с тишины — конец кусочка
WAKE_MAX = 8.0           # с — длинный кусок (музыка, разговор рядом) режем, чтобы проверить имя
# перебить: пока говорит, раз в BARGE_EVERY с разбираем последние BARGE_WIN с — не позвали ли по имени
BARGE_WIN = 2.5
BARGE_EVERY = 1.0
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
        self.paused = []                 # плееры, которые Вега поставила на паузу при вызове — после разговора снова
        self.media_touched = False       # в разговоре просили что-то с музыкой — сами не возобновляем

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
                if self.paused:
                    asyncio.create_task(self._resume_media())

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
        audio = await (record_utterance(config.mic(cfg), level, max_wait=FOLLOW_WAIT, tail=pause) if depth
                       else record_utterance(config.mic(cfg), level, tail=pause))
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
                await self.set_state("thinking")
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
            if a["name"] in ("media", "play_music"):
                self.media_touched = True
            elif a["name"] == "volume" and a["ok"] and self.paused:
                asyncio.create_task(self._resume_media(now=True))   # «сделай громче» — и сразу слышно музыку
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

    # ── слово-активатор: микрофон открыт, пока ждём имя; кусочки речи — в Whisper, пока пишутся следующие
    async def wake_loop(self):
        while True:
            cfg = config.load()
            if not cfg["wake"]:
                await asyncio.sleep(2)
                continue
            if self._wake_paused():
                await asyncio.sleep(0.3)
                continue
            try:
                async with Mic(config.mic(cfg)) as mic:
                    await self.wake_listen(cfg, mic.frames())
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print("wake:", repr(e), flush=True)
                await asyncio.sleep(3)

    def _wake_paused(self):
        """Имя не ждём, когда служба слушает сама (вопрос, продолжение разговора) или слово выключено.
        Пока думает и говорит — ждём: позвал по имени — перебил."""
        cfg = config.load()
        return not cfg["wake"] or not cfg.get("enabled", True) or self.busy() and self.state in ("listening", "transcribing")

    def _echo(self, words, barge) -> bool:
        """Своё имя из колонок: пока говорит — если оно было в её речи, сразу после — если только что."""
        own = lambda t: wake(t, words) is not None
        if barge:
            return self.voice.said_recently(own, 20)
        return time.monotonic() - self.voice.idle_at < 2.0 and self.voice.said_recently(own, 30)

    async def wake_listen(self, cfg, frames):
        """Ждёт имя в потоке кадров. Микрофон не закрывается, пока Whisper разбирает кусочек: кадры копятся
        в очереди, ни слова не теряется. Раньше кусочек кончался только после «паузы в конце фразы» (до 3 с)
        и микрофон на это время закрывался — имя терялось или ответ приходил через несколько секунд."""
        queue = asyncio.Queue()

        async def pump():
            try:
                async for f in frames:
                    await queue.put(f)
            finally:
                await queue.put(None)
        reader = asyncio.create_task(pump())
        words = config.wake_words(cfg)
        vad = Vad()
        pre, seg, n, talking_for, quiet = [], [], 0, 0.0, 0.0
        ring = collections.deque(maxlen=int(BARGE_WIN * RATE / FRAME))
        since, loud = 0, False
        try:
            while (f := await queue.get()) is not None:
                n += 1
                if n % 10 == 0 and self._wake_paused():
                    return
                talking = vad.speech(vad.level(f))
                if n < 10:                                  # первые 300 мс — только шум комнаты
                    continue
                ring.append(f)
                if not self.voice.idle.is_set():           # говорит — слушаем фоном, не зовут ли
                    seg = []
                    since, loud = since + 1, loud or talking
                    if since * FRAME / RATE < BARGE_EVERY:
                        continue
                    since, heard_loud, loud = 0, loud, False
                    if not heard_loud:
                        continue
                    # в смеси двух голосов Whisper слышит её, а не тебя — с подсказкой перебили 8 из 8, без — 6
                    head = list(ring)
                    text = await self.whisper.transcribe(cfg, np.concatenate(head), prompt=f"{config.NAME}.")
                    if after_wake(text, words) is None or self._echo(words, barge=True):
                        continue
                    await self._barge()
                    await self._woke(cfg, queue, vad, text, before=False, head=head)
                    return
                since, loud = 0, False
                if not seg:
                    pre = (pre + [f])[-10:]                 # 300 мс до начала речи — не съесть первый слог
                    if talking:
                        seg, talking_for, quiet = pre[:], FRAME / RATE, 0.0
                    continue
                seg.append(f)
                talking_for += FRAME / RATE if talking else 0
                quiet = 0.0 if talking else quiet + FRAME / RATE
                if quiet < WAKE_GAP and len(seg) * FRAME / RATE < WAKE_MAX:
                    continue
                chunk, seg = seg, []
                if talking_for < 0.12:                      # щелчок, вздох; быстрое «Вега!» — 0,2 с
                    continue
                # подсказка с именем: «Вега» 77 из 90 против 70, ложных на речи без имени и в шуме — 0
                text = await self.whisper.transcribe(cfg, np.concatenate(chunk), prompt=f"{config.NAME}.")
                rest = after_wake(text, words)
                if rest is None:
                    if hint := near_name(text, words):
                        print(f"wake: похоже на имя, но не оно: «{hint}»", flush=True)
                    continue
                if self._echo(words, barge=False):
                    continue
                if self._wake_paused():
                    return
                if self.busy() or not self.voice.idle.is_set():
                    await self._barge()                     # позвали, пока думала — новое вместо старого
                await self._woke(cfg, queue, vad, text)
                return
        finally:
            reader.cancel()

    async def _barge(self):
        """Перебили по имени: замолчать и бросить прошлый ответ."""
        print("wake: перебили по имени", flush=True)
        self.voice.stop()
        job = self.job
        if job and not job.done():
            job.cancel()
            await asyncio.wait({job}, timeout=2)

    async def _woke(self, cfg, queue, vad, text, before=True, head=None):
        """Имя услышано: с вопросом — дослушать до паузы и ответить; одно имя — звук и слушать вопрос.
        head — окно, где перебили: вопрос в нём оборван посреди слова, его распознаём вместе с продолжением."""
        words = config.wake_words(cfg)
        try:
            if after_wake(text, words, before):             # «Вега, поставь…» — дослушать, вдруг ещё говоришь
                await self.set_state("listening")
                more = await self._rest_of_phrase(cfg, queue, vad)
                if self._wake_paused():                     # пока дослушивал — нажали Super+A
                    return
                if more:
                    await self.set_state("transcribing")
                    full = await self.whisper.transcribe(cfg, np.concatenate(head + more), prompt=f"{config.NAME}.") if head else None
                    if full and after_wake(full, words, before):
                        text = full
                    else:
                        text = f"{text} {await self.whisper.transcribe(cfg, np.concatenate(more))}".strip()
            print("wake: имя услышано", flush=True)
            await self.on_wake(text, cfg, before)
        finally:
            if not self.busy() and self.state != "idle":
                await self.set_state("idle")

    async def _rest_of_phrase(self, cfg, queue, vad):
        """Кадры после имени до «паузы в конце фразы» (её начало — уже прошедшие WAKE_GAP). [] — не говорил."""
        pause = float(cfg.get("pause") or 2.0)
        more, quiet, spoke = [], WAKE_GAP, False
        while quiet < pause and len(more) * FRAME / RATE < 30:
            f = await queue.get()
            if f is None:
                break
            rms = vad.level(f)
            talking = vad.speech(rms)
            more.append(f)
            spoke = spoke or talking
            quiet = 0.0 if talking else quiet + FRAME / RATE
            if len(more) % 2 == 0:
                await self.emit("level", v=round(min(1.0, rms / 6000.0), 3))
        return more if spoke else []

    def on_call(self, cfg):
        """Позвали (имя, Super+A, перебили): громкость на удобную и пауза тому, что играет."""
        self.call_volume(cfg)
        if cfg.get("pause_media", True):
            if not self.paused:
                self.media_touched = False
            asyncio.create_task(self._pause_media())

    async def _pause_media(self):
        """Музыка, видео — всё, что играет через MPRIS (Spotify, браузер, mpv), — на паузу; запомнить что."""
        try:
            players = (await base.sh("playerctl", "-l")).split()
        except Exception:
            return
        for p in players:
            try:
                if (await base.sh("playerctl", "-p", p, "status")).strip() == "Playing":
                    await base.sh("playerctl", "-p", p, "pause")
                    if p not in self.paused:
                        self.paused.append(p)
            except Exception as e:
                print("пауза:", p, repr(e), flush=True)

    async def _resume_media(self, now=False):
        """Разговор кончился — вернуть музыку. Не сразу: перебили по имени — начнётся новый, тогда ждём его.
        now — сразу, посреди разговора: «сделай громче» — громкость слышно только на музыке."""
        if not now:
            await asyncio.sleep(0.8)
            if self.busy() or self.state != "idle" or not self.voice.idle.is_set():
                return
        players, self.paused = self.paused, []
        if self.media_touched:                   # «пауза», «следующий трек», «включи …» — музыкой управлял сам
            self.media_touched = False
            return
        for p in players:
            try:
                await base.sh("playerctl", "-p", p, "play")
            except Exception as e:
                print("продолжить:", p, repr(e), flush=True)

    def call_volume(self, cfg):
        """Позвали (имя, Super+A) — громкость системы на удобную (настройка, по умолчанию 35 %)."""
        if not cfg.get("call_volume_on", True):
            return
        level = max(0, min(100, int(cfg.get("call_volume") or 35)))
        asyncio.create_task(self._set_volume(level))

    async def _set_volume(self, level):
        try:
            await base.sh("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{level / 100:.2f}")
            await base.sh("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0")
        except Exception as e:
            print("громкость:", repr(e), flush=True)

    async def on_wake(self, text, cfg, before=True):
        rest = after_wake(text, config.wake_words(cfg), before)
        if rest is None:
            return
        self.on_call(cfg)
        await self.emit("heard", text=text)
        if cfg["backend"] != "claude":
            asyncio.create_task(self.local.warm(cfg))
        if rest:
            self.start(self.ask(rest, voice=True))                # «Вега, какая погода?» — сразу вопрос
        else:
            chime.play("wake")                                    # «Вега!» — звук и слушаем вопрос
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
        if cmd in ("ask", "listen") and not cfg.get("enabled", True):
            await self.emit("error", text="Вега выключена — включить: Настройки → Ассистент")
            return
        if cmd == "ask" and msg.get("text", "").strip():
            self.voice.stop()
            self.start(self.ask(msg["text"].strip(), voice=False, speak=msg.get("speak"), to=msg.get("to")))
        elif cmd == "listen":
            if self.busy() or not self.voice.idle.is_set():
                await self.command({"cmd": "stop"})
            else:
                self.on_call(cfg)
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
            # «прослушать» в настройках присылает голос сам — файл настроек мог ещё не записаться; новое
            # прослушивание обрывает прошлое, а не встаёт за ним в очередь (ползунок тянут — звучит последнее)
            over = {k: msg[m] for k, m in (("voice", "voice"), ("voice_tone", "tone"), ("voice_speed", "speed"),
                                           ("voice_height", "height")) if msg.get(m) is not None}
            if msg.get("preview"):
                self.voice.stop()
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


def after_wake(text: str, words, before: bool = True) -> str | None:
    """Если во фразе есть имя ассистента — что к нему сказано ("" — только имя), иначе None."""
    return wake(text, words, before)                   # «эй, Вега …», «Vega, …», «Какая погода, Вега?» — по звучанию


def near_name(text: str, words) -> str | None:
    """Слово, отличающееся от имени одним звуком («Толи», «Пори»), — в журнал: видно, как Whisper слышит
    имя, и можно добавить вариант в NAME_HEARD. Чужую речь целиком не пишем."""
    keys = [sound(w) for w in words if len(sound(w)) >= 3]
    for tok in text.split():
        k = sound(tok)
        if len(k) >= 3 and any(_one_off(k, w) for w in keys):
            return tok.strip(" ,.!?")
    return None


def _one_off(a: str, b: str) -> bool:
    """Расстояние Левенштейна ровно 1."""
    if a == b or abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(x != y for x, y in zip(a, b)) == 1
    if len(a) > len(b):
        a, b = b, a
    return any(b[:i] + b[i + 1:] == a for i in range(len(b)))
