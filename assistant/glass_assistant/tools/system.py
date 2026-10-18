"""Звук, яркость, ночной режим, «не беспокоить». Яркость, ночь и уведомления — через IPC оболочки,
чтобы её ползунки и значки не разошлись с тем, что сделал ассистент."""
import re

from . import SUGGEST, base, register
from .base import Result, Tool

SINK = "@DEFAULT_AUDIO_SINK@"
INT = {"type": "integer"}
BOOL = {"type": "boolean"}


async def volume(args):
    if "mute" in args:
        await base.sh("wpctl", "set-mute", SINK, "1" if args["mute"] else "0")
        return Result(True, "Звук выключен" if args["mute"] else "Звук включён")
    if "level" in args:
        arg = f"{max(0, min(100, args['level']))}%"
    elif args.get("change"):
        arg = f"{abs(args['change'])}%{'+' if args['change'] > 0 else '-'}"
    else:
        return Result(False, "Не получилось: не сказано, какая громкость")
    await base.sh("wpctl", "set-volume", "-l", "1.0", SINK, arg)
    now = re.search(r"\d+(\.\d+)?", await base.sh("wpctl", "get-volume", SINK))      # «Volume: 0.40 [MUTED]»
    return Result(True, f"Громкость {round(float(now.group()) * 100)}%")


async def brightness(args):
    if "level" in args:
        out = await base.qs("brightness", "set", args["level"])
    elif args.get("change"):
        out = await base.qs("brightness", "change", args["change"])
    else:
        return Result(False, "Не получилось: не сказано, какая яркость")
    return Result(True, f"Яркость {int(out)}%")


async def night_light(args):
    await base.qs("night", "enable" if args["on"] else "disable")
    return Result(True, "Ночной режим включён" if args["on"] else "Ночной режим выключен")


async def do_not_disturb(args):
    await base.qs("notifs", "set", "true" if args["on"] else "false")
    return Result(True, "«Не беспокоить» включено" if args["on"] else "«Не беспокоить» выключено")


register(Tool("volume", "Громкость системы. level — точное значение 0-100, change — на сколько изменить (+/-), "
              "mute — выключить/включить звук", {"level": INT, "change": INT, "mute": BOOL}, [], volume))
register(Tool("brightness", "Яркость экрана. level 0-100 или change +/-", {"level": INT, "change": INT}, [], brightness))
register(Tool("night_light", "Ночной режим (тёплый экран)", {"on": BOOL}, ["on"], night_light))
register(Tool("do_not_disturb", "Режим «не беспокоить»", {"on": BOOL}, ["on"], do_not_disturb))
register(Tool(SUGGEST, "Вопрос сложный: нужны свежие данные из интернета, точные факты, код или долгие рассуждения. "
              "Вызови вместо ответа", {}, [], None, claude=False))
