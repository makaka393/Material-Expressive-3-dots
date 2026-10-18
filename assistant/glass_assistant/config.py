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
    "backend": "auto",           # auto — локальная модель, «морковка» — Claude; claude — всегда Claude; local — никогда
    "claude_words": ["морковь"],   # слово в начале фразы отправляет её в Claude (узнаётся по «морков…»)
    "model": "claude-opus-5-5",
    "effort": "low",             # low | medium | high — глубина размышлений Claude (ниже — быстрее)
    "speak_voice": True,         # озвучивать ответы на голосовые вопросы
    "speak_typed": False,        # и на вопросы из лаунчера
    "voice": "xenia",            # голос Silero: женские xenia, kseniya, baya; мужские aidar, eugene
    "voice_pitch": "medium",     # тон: low | medium | high
    "voice_rate": "medium",      # темп: slow | medium | fast
    "wake": False,               # слушать слово-активатор
    "follow_up": True,
    "pause": 1.3,                # с тишины — конец фразы (0,8 / 1,3 / 2); слову-активатору — столько же           # после голосового ответа слушать продолжение без слова-активатора
    # слово-активатор и его короткие формы; сравниваются по звучанию (router.wake)
    "wake_words": ["обсидиан", "обс", "обси", "обсик", "obsidian", "obs"],
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
