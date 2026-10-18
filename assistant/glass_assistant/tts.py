"""Голос ассистента: Silero TTS (русский, на процессоре) и воспроизведение через PipeWire (pw-play).

Ответ озвучивается по предложениям: первое уже звучит, пока модель дописывает остальные, следующее
синтезируется, пока играет текущее (синтез и проигрывание — две задачи), и всё — в один pw-play, без
запуска проигрывателя перед каждой фразой. Модель грузится и разогревается при запуске службы.
"""
import asyncio
import os
import re

from . import config
from .numbers import spoken

RATE = 48000
LINGER = 0.3          # с — ждём следующую фразу, прежде чем закрыть проигрыватель


class Voice:
    def __init__(self, spawn=None):
        self.model = None
        self.spawn = spawn or self._spawn
        self.texts = asyncio.Queue()     # (поколение, текст, голос) — ждут синтеза
        self.pcms = asyncio.Queue()      # (поколение, звук) — ждут проигрывателя
        self.synthesizing = False
        self.proc = None                 # pw-play текущего ответа
        self.gen = 0                     # растёт при stop(): всё, что было в очередях, уже не нужно
        self.idle = asyncio.Event()
        self.idle.set()
        self.tasks = None

    def _load(self, path):
        import torch
        torch.set_num_threads(max(1, (os.cpu_count() or 8) // 2))      # 8 потоков — на треть быстрее 4
        model = torch.package.PackageImporter(path).load_pickle("tts_models", "model")
        model.to(torch.device("cpu"))
        return model

    async def ready(self, cfg):
        if self.model is None:
            self.model = await asyncio.to_thread(self._load, cfg["tts_model"])
            try:                         # первый синтез после загрузки в разы медленнее — сделать его сразу
                await asyncio.to_thread(self._synth, "Привет.", (cfg["voice"], "medium", "medium"))
            except Exception as e:
                print("tts: разогрев:", e, flush=True)
        if self.tasks is None:
            self.tasks = [asyncio.create_task(self._synth_loop()), asyncio.create_task(self._play_loop())]

    async def _spawn(self):
        return await asyncio.create_subprocess_exec(
            "pw-play", "--raw", "--format", "f32", "--rate", str(RATE), "--channels", "1",
            "--media-role", "Assistant", "-", stdin=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)

    def _synth(self, text, voice):
        speaker, pitch, rate = voice
        if (pitch, rate) == ("medium", "medium"):
            src = {"text": text}
        else:                            # тон и темп — через SSML: тот же голос ниже/выше, медленнее/быстрее
            safe = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            src = {"ssml_text": f'<speak><prosody pitch="{pitch}" rate="{rate}">{safe}</prosody></speak>'}
        try:
            audio = self.model.apply_tts(**src, speaker=speaker, sample_rate=RATE, put_accent=True, put_yo=True,
                                         put_stress_homo=True, put_yo_homo=True)
        except TypeError:                # у разных версий моделей свой набор параметров
            audio = self.model.apply_tts(**src, speaker=speaker, sample_rate=RATE)
        return audio.numpy().astype("float32").tobytes()

    async def say(self, text: str, cfg):
        """В очередь на озвучку (одно предложение или фраза)."""
        text = speakable(text)
        if not text:
            return
        await self.ready(cfg)
        self.idle.clear()
        await self.texts.put((self.gen, text, (cfg["voice"], cfg["voice_pitch"], cfg["voice_rate"])))

    def _more(self):
        return not self.texts.empty() or self.synthesizing or not self.pcms.empty()

    async def _synth_loop(self):
        while True:
            gen, text, voice = await self.texts.get()
            self.synthesizing = True
            pcm = None
            if gen == self.gen:
                try:
                    pcm = await asyncio.to_thread(self._synth, text, voice)
                except Exception as e:   # кривой текст не должен ронять озвучку
                    print("tts:", e, flush=True)
            self.synthesizing = False
            if pcm is not None and gen == self.gen:
                await self.pcms.put((gen, pcm))
            else:
                self._maybe_idle()

    async def _play_loop(self):
        while True:
            gen, pcm = await self.pcms.get()
            proc = None
            while True:                  # один ответ — один pw-play
                if gen == self.gen:
                    if proc is None or proc is not self.proc:     # первый кусок или после stop()
                        proc = self.proc = await self.spawn()
                    try:
                        proc.stdin.write(pcm)
                        await proc.stdin.drain()
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                try:                     # дальше ещё будет — ждём сколько надо; иначе чуть-чуть
                    gen, pcm = await asyncio.wait_for(self.pcms.get(), None if self._more() else LINGER)
                except asyncio.TimeoutError:
                    break
            if proc is not None and proc is self.proc:
                try:
                    proc.stdin.close()
                except (BrokenPipeError, ConnectionResetError):
                    pass
                await proc.wait()        # доиграть то, что уже в буфере
                if proc is self.proc:
                    self.proc = None
            self._maybe_idle()

    def _maybe_idle(self):
        if not self._more() and self.proc is None:
            self.idle.set()

    def stop(self):
        """Замолчать сразу и забыть очереди."""
        self.gen += 1
        for q in (self.texts, self.pcms):
            while not q.empty():
                q.get_nowait()
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
        self.proc = None
        self.idle.set()


SENT_END = re.compile(r"(?<=[.!?…])\s+|\n+")


FIRST_CUT = re.compile(r"[,;:](?=\s)|\s[—–](?=\s)")


class Sentences:
    """Режет поток текста на предложения для озвучки. Первую реплику — уже по запятой, если до неё
    набралось ≥ 20 знаков: звук пойдёт раньше, чем модель допишет длинное предложение."""

    def __init__(self):
        self.buf = ""
        self.first = True

    def feed(self, chunk: str):
        self.buf += chunk
        if self.first and not SENT_END.search(self.buf):
            m = next((m for m in FIRST_CUT.finditer(self.buf) if m.start() >= 20), None)
            if not m:
                return []
            head, self.buf, self.first = self.buf[:m.end()].strip(), self.buf[m.end():].lstrip(), False
            return [head]
        out, start, acc = [], 0, ""
        for m in SENT_END.finditer(self.buf):
            piece = self.buf[start:m.start()].strip()
            start = m.end()
            acc = f"{acc} {piece}".strip()
            if len(acc) >= 12:                   # «Да.» склеиваем со следующим — меньше пауз
                out.append(acc)
                acc = ""
                self.first = False
        rest = self.buf[start:]
        self.buf = f"{acc} {rest}" if acc else rest
        return out

    def flush(self):
        head, self.buf = self.buf.strip(), ""
        return [head] if head else []


def speakable(text: str) -> str:
    """Убрать то, что вслух не читают (разметку, ссылки, эмодзи), а числа — словами: Silero цифры глотает."""
    t = re.sub(r"https?://\S+", "", text)
    t = re.sub(r"`{1,3}[^`]*`{1,3}", "", t)
    t = re.sub(r"[*_#>|~^]+", "", t)
    t = re.sub(r"[\U0001F000-\U0001FFFF☀-➿]", "", t)
    t = t.replace("—", ", ").replace("–", ", ")
    return spoken(" ".join(t.split()).strip())
