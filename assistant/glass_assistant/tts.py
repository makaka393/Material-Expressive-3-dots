"""Голос ассистента: Silero TTS (русский, на процессоре) и воспроизведение через PipeWire (pw-play).

Ответ озвучивается по предложениям: первое уже звучит, пока модель дописывает остальные,
следующее синтезируется, пока играет текущее.
"""
import asyncio
import re

from . import config

RATE = 48000


class Voice:
    def __init__(self):
        self.model = None
        self.play = None                 # текущий pw-play
        self.queue = asyncio.Queue()
        self.gen = 0                     # растёт при stop(): всё, что было в очереди, уже не нужно
        self.speaking = asyncio.Event()  # что-то звучит или ждёт очереди
        self.idle = asyncio.Event()
        self.idle.set()
        self.task = None

    def _load(self, path):
        import torch
        torch.set_num_threads(4)
        model = torch.package.PackageImporter(path).load_pickle("tts_models", "model")
        model.to(torch.device("cpu"))
        return model

    async def ready(self, cfg):
        if self.model is None:
            self.model = await asyncio.to_thread(self._load, cfg["tts_model"])
        if self.task is None:
            self.task = asyncio.create_task(self._worker())

    def _synth(self, text, speaker):
        try:
            audio = self.model.apply_tts(text=text, speaker=speaker, sample_rate=RATE, put_accent=True, put_yo=True,
                                         put_stress_homo=True, put_yo_homo=True)
        except TypeError:                # у разных версий моделей свой набор параметров
            audio = self.model.apply_tts(text=text, speaker=speaker, sample_rate=RATE)
        return audio.numpy().astype("float32").tobytes()

    async def say(self, text: str, cfg):
        """В очередь на озвучку (одно предложение или фраза)."""
        text = speakable(text)
        if not text:
            return
        await self.ready(cfg)
        self.idle.clear()
        await self.queue.put((self.gen, text, cfg["voice"]))

    async def _worker(self):
        pending = None                   # уже синтезированное следующее
        while True:
            gen, text, speaker = pending or await self.queue.get()
            pending = None
            if gen != self.gen:
                self._maybe_idle()
                continue
            try:
                pcm = await asyncio.to_thread(self._synth, text, speaker)
            except Exception as e:       # кривой текст не должен ронять озвучку
                print("tts:", e, flush=True)
                self._maybe_idle()
                continue
            if gen != self.gen:
                self._maybe_idle()
                continue
            self.play = await asyncio.create_subprocess_exec(
                "pw-play", "--raw", "--format", "f32", "--rate", str(RATE), "--channels", "1",
                "--media-role", "Assistant", "-", stdin=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
            try:
                self.play.stdin.write(pcm)
                await self.play.stdin.drain()
                self.play.stdin.close()
            except (BrokenPipeError, ConnectionResetError):
                pass
            await self.play.wait()
            self.play = None
            self._maybe_idle()

    def _maybe_idle(self):
        if self.queue.empty() and self.play is None:
            self.idle.set()

    def stop(self):
        """Замолчать сразу и забыть очередь."""
        self.gen += 1
        while not self.queue.empty():
            self.queue.get_nowait()
        if self.play and self.play.returncode is None:
            self.play.terminate()
        self.idle.set()


SENT_END = re.compile(r"(?<=[.!?…])\s+|\n+")


class Sentences:
    """Режет поток текста на предложения для озвучки."""

    def __init__(self):
        self.buf = ""

    def feed(self, chunk: str):
        self.buf += chunk
        out, start, acc = [], 0, ""
        for m in SENT_END.finditer(self.buf):
            piece = self.buf[start:m.start()].strip()
            start = m.end()
            acc = f"{acc} {piece}".strip()
            if len(acc) >= 12:                   # «Да.» склеиваем со следующим — меньше пауз
                out.append(acc)
                acc = ""
        rest = self.buf[start:]
        self.buf = f"{acc} {rest}" if acc else rest
        return out

    def flush(self):
        head, self.buf = self.buf.strip(), ""
        return [head] if head else []


def speakable(text: str) -> str:
    """Убрать то, что вслух не читают: разметку, ссылки, эмодзи."""
    t = re.sub(r"https?://\S+", "", text)
    t = re.sub(r"`{1,3}[^`]*`{1,3}", "", t)
    t = re.sub(r"[*_#>|~^]+", "", t)
    t = re.sub(r"[\U0001F000-\U0001FFFF☀-➿]", "", t)
    t = t.replace("—", ", ").replace("–", ", ")
    return " ".join(t.split()).strip()
