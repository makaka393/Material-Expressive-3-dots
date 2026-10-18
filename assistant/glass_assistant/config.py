"""Настройки ассистента: ~/.config/glass/assistant.json (недостающее — по умолчанию).

Файл перечитывается при каждом запросе — правка в настройках оболочки действует сразу.
"""
import json
import os
import re
from pathlib import Path

HOME = Path.home()
DATA = Path(os.environ.get("GLASS_ASSISTANT_DATA", HOME / ".local/share/glass-assistant"))
CONFIG = Path(os.environ.get("GLASS_ASSISTANT_CONFIG", HOME / ".config/glass/assistant.json"))
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
SOCKET = RUNTIME / "glass-assistant.sock"

DEFAULTS = {
    "backend": "auto",           # auto — локальная модель, «морковь» — Claude; claude — всегда Claude; local — никогда
    "claude_words": ["морковь"],   # слово в начале фразы отправляет её в Claude (узнаётся по «морков…»)
    "model": "claude-opus-5-5",
    "effort": "low",             # low | medium | high — глубина размышлений Claude (ниже — быстрее)
    "speak_voice": True,         # озвучивать ответы на голосовые вопросы
    "speak_typed": False,        # и на вопросы из лаунчера
    "voice": "xenia",            # голос Silero: женские xenia, kseniya, baya; мужские aidar, eugene
    "voice_tone": 0.0,           # тон: −1 мягче … +1 твёрже (tts.prosody, tts.shape)
    "voice_speed": 1.0,          # скорость: 0,75 … 1,35
    "voice_height": 0.0,         # высота: −1 ниже … +1 выше (±15 %)
    "wake": False,               # слушать имя
    "follow_up": True,           # после голосового ответа слушать продолжение без имени
    "pause": 2.0,                # с тишины — конец фразы (1,5 / 2 / 3)
    "wake_words": [],            # ещё слова-активаторы, кроме имени; сравниваются по звучанию (router.wake)
    "mic": "",                   # источник PipeWire (пусто — микрофон по умолчанию)
    "language": "ru",
    "history_turns": 20,         # столько реплик помнит разговор, потом начинает заново
    "history_idle_min": 10,      # и после такой паузы
    "local_model": str(DATA / "models/llm/gemma-4-E4B-it-Q4_K_M.gguf"),
    "local_idle_min": 30,        # локальная модель выгружается из видеопамяти после простоя
    "local_history_turns": 6,    # столько реплик помнит разговор с локальной моделью
    "whisper_model": str(DATA / "models/whisper/ggml-large-v3-turbo-q5_0.bin"),
    "whisper_idle_min": 15,
    "tts_model": str(DATA / "models/tts/v5_ru.pt"),
}


# Имя ассистента — оно же слово-активатор. Синтез 5 голосами, тон/темп, с шумом → Whisper: «Тори» — 81 из 90,
# «Ирис» — 64 («И рис», «Ирина», «Юрис»), «Ари» — 76, «Вега» — 69. «Торик» — так Whisper пишет имя, сказанное отдельно
NAME = "Тори"
NAME_HEARD = ["тори", "tori", "торик"]
FEMALE = {"xenia", "kseniya", "baya"}         # голоса Silero; aidar, eugene — мужские


def wake_words(cfg) -> list:
    return NAME_HEARD + list(cfg.get("wake_words") or [])


def female(cfg) -> bool:
    return cfg.get("voice", DEFAULTS["voice"]) in FEMALE


def load() -> dict:
    cfg = dict(DEFAULTS)
    try:
        data = json.loads(CONFIG.read_text())
    except (OSError, ValueError):
        data = {}
    # оболочка пишет ключи в camelCase (speakVoice), здесь — snake_case (speak_voice)
    for k, v in data.items():
        cfg[re.sub(r"(?<!^)(?=[A-Z])", "_", k).lower()] = v
    return cfg


def has_key() -> bool:
    return bool(os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")
                or (HOME / ".config/anthropic").exists())
