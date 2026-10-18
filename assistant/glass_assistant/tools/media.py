"""Плеер: то, что уже играет (Spotify, браузер — любой MPRIS через playerctl)."""
from . import base, register
from .base import Result, Tool

SIMPLE = {"play": ("play", "Играет"), "pause": ("pause", "Пауза"), "toggle": ("play-pause", "Пауза/продолжить"),
          "next": ("next", "Следующий трек"), "previous": ("previous", "Предыдущий трек")}


async def media(args):
    action, secs = args.get("action"), int(args.get("seconds") or 10)
    if action == "seek_forward":
        argv, show = ("position", f"{secs}+"), f"Вперёд на {secs} с"
    elif action == "seek_back":
        argv, show = ("position", f"{secs}-"), f"Назад на {secs} с"
    elif action in SIMPLE:
        argv, show = (SIMPLE[action][0],), SIMPLE[action][1]
    else:
        return Result(False, f"Не получилось: непонятное действие {action}")
    try:
        await base.sh("playerctl", *argv)
    except RuntimeError as e:
        if "No players" in str(e):
            return Result(False, "Не получилось: плеер не запущен")
        raise
    return Result(True, show)


register(Tool(
    "media",
    "Управление тем, что уже играет: пауза, продолжить («включи музыку» без названия — play), "
    "следующий/предыдущий трек («следующую», «скип»), перемотка",
    {"action": {"type": "string", "enum": ["play", "pause", "toggle", "next", "previous", "seek_forward", "seek_back"]},
     "seconds": {"type": "integer", "description": "для перемотки"}},
    ["action"], media))
