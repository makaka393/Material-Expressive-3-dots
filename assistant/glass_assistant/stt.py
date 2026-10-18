"""Уши ассистента: микрофон через PipeWire (pw-record), детектор речи по громкости и Whisper
(whisper.cpp на видеокарте, whisper-server — грузится по требованию и выгружается после простоя).
"""
import asyncio
import io
import os
import time
import wave

import httpx2
import numpy as np

from . import config

RATE = 16000
FRAME = 480                       # 30 мс


class Mic:
    """Поток кадров с микрофона: 16 кГц, моно, int16."""

    def __init__(self, source: str = ""):
        self.source = source
        self.proc = None

    async def __aenter__(self):
        args = ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16"]
        if self.source:
            args += ["--target", self.source]
        self.proc = await asyncio.create_subprocess_exec(*args, "-", stdout=asyncio.subprocess.PIPE,
                                                         stderr=asyncio.subprocess.DEVNULL)
        return self

    async def frames(self):
        while True:
            data = await self.proc.stdout.readexactly(FRAME * 2)
            yield np.frombuffer(data, dtype=np.int16)

    async def __aexit__(self, *exc):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
            await self.proc.wait()


class Vad:
    """Речь или тишина по громкости кадра относительно шума в комнате (порог подстраивается сам)."""

    def __init__(self):
        self.floor = 300.0

    def level(self, frame) -> float:
        return float(np.sqrt(np.mean(frame.astype(np.float32) ** 2)))

    def speech(self, rms: float) -> bool:
        loud = rms > max(self.floor * 3.0, 450.0)
        if not loud:                                  # шум считаем только по тихим кадрам
            self.floor = 0.97 * self.floor + 0.03 * max(rms, 50.0)
        return loud


async def record_utterance(source, on_level, max_wait=6.0, max_len=30.0, tail=2.0, frames=None):
    """Ждёт начала речи (до max_wait с) и пишет до паузы tail с (настройка «пауза в конце фразы»: при 0,75 с
    фразу обрывало на раздумье посреди неё). Возвращает int16 или None. frames — кадры вместо микрофона (тесты)."""
    if frames is not None:
        return await _collect(frames, on_level, max_wait, max_len, tail)
    async with Mic(source) as mic:
        return await _collect(mic.frames(), on_level, max_wait, max_len, tail)


async def _collect(frames, on_level, max_wait, max_len, tail):
    vad = Vad()
    chunks, started, quiet, n = [], False, 0.0, 0
    pre = []                                          # 300 мс до начала речи — не съесть первый слог
    async for frame in frames:
        n += 1
        rms = vad.level(frame)
        if n % 2 == 0:
            await on_level(min(1.0, rms / 6000.0))
        if n < 8:                                     # первые 240 мс — только шум комнаты
            vad.speech(rms)
            continue
        talking = vad.speech(rms)
        if not started:
            pre = (pre + [frame])[-10:]
            if talking:
                started, chunks = True, pre[:]
            elif n * FRAME / RATE > max_wait:         # по кадрам, а не по часам: тесты идут быстрее речи
                return None
            continue
        chunks.append(frame)
        quiet = 0.0 if talking else quiet + FRAME / RATE
        if quiet >= tail or len(chunks) * FRAME / RATE >= max_len:
            break
    if not chunks:
        return None
    audio = np.concatenate(chunks)
    return audio if len(audio) > RATE * 0.35 else None


def to_wav(audio) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(audio.tobytes())
    return buf.getvalue()


class Whisper:
    PORT = 8092

    def __init__(self):
        self.proc = None
        self.used = 0.0
        self.lock = asyncio.Lock()
        self.exe = str(config.DATA / "src/whisper.cpp/build/bin/whisper-server")

    @property
    def url(self):
        return f"http://127.0.0.1:{self.PORT}"

    async def ensure(self, cfg):
        async with self.lock:
            self.used = time.monotonic()
            if self.proc and self.proc.returncode is None:
                return
            if not os.path.exists(self.exe) or not os.path.exists(cfg["whisper_model"]):
                raise RuntimeError("Whisper не установлен")
            log = open(config.DATA / "logs/whisper-server.log", "ab")
            self.proc = await asyncio.create_subprocess_exec(
                self.exe, "-m", cfg["whisper_model"], "--host", "127.0.0.1", "--port", str(self.PORT),
                "-l", cfg["language"], "-nt", "-fa", stdout=log, stderr=log)
            async with httpx2.AsyncClient() as http:
                for _ in range(120):
                    if self.proc.returncode is not None:
                        raise RuntimeError("whisper-server не запустился (см. logs/whisper-server.log)")
                    try:
                        await http.get(self.url + "/", timeout=1)
                        return
                    except httpx2.HTTPError:
                        await asyncio.sleep(0.25)
            raise RuntimeError("whisper-server не ответил")

    async def transcribe(self, cfg, audio) -> str:
        await self.ensure(cfg)
        async with httpx2.AsyncClient(timeout=30) as http:
            r = await http.post(self.url + "/inference",
                                files={"file": ("speech.wav", to_wav(audio), "audio/wav")},
                                data={"response_format": "json", "temperature": "0.0", "language": cfg["language"]})
            r.raise_for_status()
        self.used = time.monotonic()
        return clean(r.json().get("text", ""))

    async def reap(self, cfg, keep: bool):
        if keep or not (self.proc and self.proc.returncode is None):
            return
        if time.monotonic() - self.used > cfg["whisper_idle_min"] * 60:
            self.proc.terminate()
            await self.proc.wait()
            self.proc = None

    async def stop(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
            await self.proc.wait()


# Whisper на тишине и шуме иногда «слышит» титры из обучающих данных
HALLUCINATIONS = ("субтитры", "продолжение следует", "спасибо за просмотр", "редактор субтитров", "подписывайтесь")


def clean(text: str) -> str:
    t = " ".join(text.replace("\n", " ").split()).strip()
    low = t.lower()
    if not t or any(h in low for h in HALLUCINATIONS) or low.strip(" .!?…") in ("", "ммм", "м", "а"):
        return ""
    return t
