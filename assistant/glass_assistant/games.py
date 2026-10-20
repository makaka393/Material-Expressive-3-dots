"""Игровой режим: пока идёт игра, видеокарта вся её. Whisper и локальная модель выгружены и не грузятся,
голосом Вега не слушает: слово-активатор гонял Whisper на звуке игры — до целого ядра процессора и
гигабайт видеопамяти. Claude («морковь», текстом) и таймеры с будильниками работают — им видеокарта
не нужна.

Идёт ли игра — по метке $XDG_RUNTIME_DIR/glass-game. Её ставит и снимает игровой режим оболочки
(~/.config/hypr/scripts/gamemode-start.sh и gamemode-end.sh): их зовут gamemode (игры через
gamemoderun) и game-watch.sh, который сам находит игры Steam, Proton и Mobile Legends.
"""
from . import config

MARK = config.RUNTIME / "glass-game"
TEXT = "Пока идёт игра, Вега спит: видеокарта вся игре"

playing = False


class Gaming(RuntimeError):
    """Нужны Whisper или локальная модель, а идёт игра."""


def check():
    if playing:
        raise Gaming(TEXT)
