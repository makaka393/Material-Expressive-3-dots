"""Оболочка и система: скриншот, запись экрана, блокировка, обои, Wi-Fi и Bluetooth."""
import random
import re
from pathlib import Path

from . import base, register
from .base import Result, Tool

SCRIPTS = Path.home() / ".config/hypr/scripts"
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4", ".webm", ".mkv", ".mov"}
SHOTS = {"full": "Скриншот экрана", "region": "Выдели область", "pretty": "Выдели — сделаю скриншот в рамке",
         "lens": "Выдели — отправлю в Google Lens"}


def wallpaper_dir() -> Path:
    """Папка обоев оболочки (Theme.qml → wallpaperDir)."""
    try:
        t = (Path.home() / ".config/quickshell/glass/Theme.qml").read_text()
        m = re.search(r'wallpaperDir:\s*Quickshell\.env\("HOME"\)\s*\+\s*"([^"]+)"', t)
        if m:
            return Path.home() / m.group(1).lstrip("/")
    except OSError:
        pass
    return Path.home() / "Downloads/Wallpapers"


async def screenshot(args):
    area = args.get("area") if args.get("area") in SHOTS else "full"
    await base.launch(str(SCRIPTS / "screenshot.sh"), area)
    return Result(True, SHOTS[area])


async def screen_record(args):
    if args["action"] == "stop":
        await base.launch(str(SCRIPTS / "record.sh"), "stop")
        return Result(True, "Останавливаю запись")
    await base.launch(str(SCRIPTS / "record.sh"), "start", "full", "1", "0", "0")       # весь экран, со звуком
    return Result(True, "Пишу экран")


async def lock_screen(args):
    await base.qs("lock", "lock")
    return Result(True, "Блокирую экран")


async def wallpaper(args):
    d = wallpaper_dir()
    files = [p for p in d.iterdir() if p.suffix.lower() in EXTS] if d.is_dir() else []
    if not files:
        return Result(False, f"Нет обоев в {d}", "Не нашёл обоев.")
    await base.launch(str(SCRIPTS / "changetheme.sh"), str(random.choice(files)))
    return Result(True, "Меняю обои")


async def radio(args):
    on = "on" if args["on"] else "off"
    if args["device"] == "wifi":
        await base.sh("nmcli", "radio", "wifi", on)
        return Result(True, "Wi-Fi " + ("включён" if args["on"] else "выключен"))
    await base.sh("bluetoothctl", "power", on, timeout=3)          # bluetoothctl умеет зависать
    return Result(True, "Bluetooth " + ("включён" if args["on"] else "выключен"))


register(Tool("screenshot", "Скриншот: full — весь экран, region — выделить область, pretty — область в красивой рамке, "
              "lens — область в Google Lens", {"area": {"type": "string", "enum": list(SHOTS)}}, [], screenshot))
register(Tool("screen_record", "Запись экрана: начать или остановить", {"action": {"type": "string", "enum": ["start", "stop"]}},
              ["action"], screen_record))
register(Tool("lock_screen", "Заблокировать экран", {}, [], lock_screen))
register(Tool("wallpaper", "Сменить обои на случайные из папки обоев (цвета темы — по ним)", {}, [], wallpaper))
register(Tool("radio", "Включить или выключить Wi-Fi или Bluetooth",
              {"device": {"type": "string", "enum": ["wifi", "bluetooth"]}, "on": {"type": "boolean"}}, ["device", "on"], radio))
