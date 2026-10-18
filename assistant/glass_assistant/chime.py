"""Короткий звук «слушаю» после слова-активатора: без него не понять, услышал ли ассистент, если не
смотришь на экран. Два мягких тона вверх; wav создаётся один раз в $XDG_RUNTIME_DIR."""
import subprocess
import wave

import numpy as np

from . import config

RATE = 48000
NOTES = {"wake": (659.3, 880.0), "done": (880.0, 659.3),    # ми → ля вверх; обратно — «готово»
         "alarm": (880.0, 1046.5, 880.0, 1046.5, 880.0, 1046.5)}


def _make(kind: str):
    path = config.RUNTIME / f"glass-chime-{kind}.wav"
    if path.exists():
        return path
    parts = []
    for f in NOTES[kind]:
        t = np.arange(int(RATE * 0.09)) / RATE
        env = np.minimum(1, t / 0.008) * np.exp(-t * 18)            # мягкая атака, быстрое затухание
        parts.append(np.sin(2 * np.pi * f * t) * env)
    audio = (np.concatenate(parts) * 0.5 * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(audio.tobytes())
    return path


def play(kind: str = "wake"):
    try:
        subprocess.Popen(["pw-play", "--volume", "0.35", str(_make(kind))],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as e:
        print("звук:", e, flush=True)
