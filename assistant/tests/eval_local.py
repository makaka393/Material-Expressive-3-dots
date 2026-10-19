"""Оценка локальной модели на живом llama-server: верно ли выбирает действия и как быстро.

Не входит в unittest (имя без test_): нужна видеокарта и ~3,3 ГБ видеопамяти. Действия не выполняются —
инструменты подменены записью вызовов. Запуск из assistant/:
    python -m tests.eval_local            вопросы как из лаунчера
    python -m tests.eval_local --voice    как голосом (с указанием про озвучку)
"""
import asyncio
import json
import statistics
import tempfile
from pathlib import Path
import sys
import time
from unittest.mock import patch

from glass_assistant import config, memory, tools
from glass_assistant.memory import Memory
from glass_assistant.local import LocalBrain, LocalServer
from glass_assistant.tools.base import Result


def low(v):
    return str(v or "").lower()


def arg(c, k):
    return c["args"].get(k)


def n(v):
    return v if isinstance(v, (int, float)) else 0


# (фраза, ожидание): ожидание — список (инструмент, проверка) | "chat" (ответ словами, без действий)
CASES = [
    ("поставь на паузу", [("media", lambda c: arg(c, "action") in ("pause", "toggle"))]),
    ("следующий трек", [("media", lambda c: arg(c, "action") == "next")]),
    ("скип", [("media", lambda c: arg(c, "action") == "next")]),
    ("следуюший трэк", [("media", lambda c: arg(c, "action") == "next")]),
    ("верни предыдущую песню", [("media", lambda c: arg(c, "action") == "previous")]),
    ("перемотай на 30 секунд вперёд", [("media", lambda c: arg(c, "action") == "seek_forward" and arg(c, "seconds") == 30)]),
    ("продолжи музыку", [("media", lambda c: arg(c, "action") in ("play", "toggle"))]),
    ("включи музыку", [("media", lambda c: arg(c, "action") in ("play", "toggle"))]),
    ("выключи музыку", [("media", lambda c: arg(c, "action") in ("pause", "toggle"))]),
    ("сделай громче", [("volume", lambda c: n(arg(c, "change")) > 0)]),
    ("громкость на 30", [("volume", lambda c: arg(c, "level") == 30)]),
    ("выключи звук", [("volume", lambda c: arg(c, "mute") is True)]),
    ("эээ слушай можешь сделать потише немного", [("volume", lambda c: n(arg(c, "change")) < 0)]),
    ("звук на половину", [("volume", lambda c: arg(c, "level") == 50)]),
    ("громко слишком", [("volume", lambda c: n(arg(c, "change")) < 0 or n(arg(c, "level")) and arg(c, "level") < 50)]),
    ("убавь яркость", [("brightness", lambda c: n(arg(c, "change")) < 0)]),
    ("яркость на максимум", [("brightness", lambda c: arg(c, "level") == 100)]),
    ("выкрути яркость на максимум", [("brightness", lambda c: arg(c, "level") == 100)]),
    ("включи ночной режим", [("night_light", lambda c: arg(c, "on") is True)]),
    ("выключи ночной режим", [("night_light", lambda c: arg(c, "on") is False)]),
    ("включи режим не беспокоить", [("do_not_disturb", lambda c: arg(c, "on") is True)]),
    ("отключи не беспокоить", [("do_not_disturb", lambda c: arg(c, "on") is False)]),
    ("громче и следующий трек", [("volume", lambda c: n(arg(c, "change")) > 0), ("media", lambda c: arg(c, "action") == "next")]),
    ("сделай яркость поменьше и включи ночник", [("brightness", lambda c: n(arg(c, "change")) < 0), ("night_light", lambda c: arg(c, "on") is True)]),
    ("привет, как дела", "chat"),
    ("сколько будет 17 умножить на 23", "chat"),
    ("спасибо", "chat"),
    ("я устал", "chat"),
    ("как выключить компьютер в линуксе", "chat"),
    ("не выключай компьютер, я ещё работаю", "chat"),
    # приложения, сайты, окна, вкладки, музыка
    ("открой браузер", [("open_app", lambda c: any(w in low(arg(c, "name")) for w in ("браузер", "browser", "zen")))]),
    ("открой телегу", [("open_app", lambda c: "телег" in low(arg(c, "name")) or "telegram" in low(arg(c, "name")))]),
    ("запусти стим", [("open_app", lambda c: "стим" in low(arg(c, "name")) or "steam" in low(arg(c, "name")))]),
    ("закрой дискорд", [("close_app", lambda c: "дискорд" in low(arg(c, "name")) or "discord" in low(arg(c, "name")))]),
    ("найди на ютубе как сделать пиццу", [("web_search", lambda c: arg(c, "site") == "youtube" and "пицц" in low(arg(c, "query")))]),
    ("загугли курс доллара", [("web_search", lambda c: "доллар" in low(arg(c, "query")))]),
    ("открой гитхаб", ([("open_url", lambda c: "github" in low(arg(c, "url")))],
                       [("open_app", lambda c: "github" in low(arg(c, "name")) or "гитхаб" in low(arg(c, "name")))])),
    ("следующая вкладка", [("browser_tab", lambda c: arg(c, "action") == "next")]),
    ("закрой вкладку", [("browser_tab", lambda c: arg(c, "action") == "close")]),
    ("открой новую вкладку", [("browser_tab", lambda c: arg(c, "action") == "new")]),
    ("переключись на третью вкладку", [("browser_tab", lambda c: arg(c, "action") == "number" and arg(c, "number") == 3)]),
    ("перейди на второй рабочий стол", [("workspace", lambda c: arg(c, "number") == 2)]),
    ("следующий рабочий стол", [("workspace", lambda c: arg(c, "direction") == "next")]),
    ("перекинь окно на пятый", [("move_window", lambda c: arg(c, "workspace") == 5)]),
    ("закрой это окно", [("window", lambda c: arg(c, "action") == "close")]),
    ("разверни окно на весь экран", [("window", lambda c: arg(c, "action") == "fullscreen")]),
    ("включи linkin park", [("play_music", lambda c: "linkin" in low(arg(c, "query")))]),
    ("поставь песню numb", [("play_music", lambda c: "numb" in low(arg(c, "query")))]),
    ("вруби что-нибудь из кино", [("play_music", lambda c: "кино" in low(arg(c, "query")))]),
    ("включи другую песню", [("media", lambda c: arg(c, "action") == "next")]),
    # память: запомнить, забыть, вспомнить (во временной памяти уже есть «Пользователя зовут Рома»)
    ("запомни, что я люблю linkin park", [("remember", lambda c: "linkin" in low(arg(c, "fact")))]),
    ("запомни что моя машина ауди", [("remember", lambda c: "ауди" in low(arg(c, "fact")) or "audi" in low(arg(c, "fact")))]),
    ("забудь про мою машину", [("forget", lambda c: "машин" in low(arg(c, "what")))]),
    ("как меня зовут", "chat:ром"),
    ("что ты обо мне знаешь", "chat:ром"),
    # оболочка, справка, таймеры, питание
    ("выключи компьютер", [("power", lambda c: arg(c, "action") == "shutdown")]),
    ("перезагрузи комп", [("power", lambda c: arg(c, "action") == "reboot")]),
    ("заблокируй экран", [("lock_screen", lambda c: True)]),
    ("сделай скриншот области", [("screenshot", lambda c: arg(c, "area") == "region")]),
    ("начни запись экрана", [("screen_record", lambda c: arg(c, "action") == "start")]),
    ("смени обои", [("wallpaper", lambda c: True)]),
    ("выключи вайфай", [("radio", lambda c: arg(c, "device") == "wifi" and arg(c, "on") is False)]),
    ("какая погода", [("system_info", lambda c: arg(c, "kind") == "weather")]),
    ("сколько времени", ([("system_info", lambda c: arg(c, "kind") == "time")], "chat")),
    ("насколько загружен процессор", [("system_info", lambda c: arg(c, "kind") == "cpu")]),
    ("есть ли у меня стим", [("system_info", lambda c: arg(c, "kind") == "apps" and "ст" in low(arg(c, "query")) or "steam" in low(arg(c, "query")))]),
    ("какие программы у меня установлены", [("system_info", lambda c: arg(c, "kind") == "apps")]),
    ("как там видеокарта, не греется", [("system_info", lambda c: arg(c, "kind") == "gpu")]),
    ("что сейчас играет", [("system_info", lambda c: arg(c, "kind") == "now_playing")]),
    ("сколько заряда в наушниках", [("system_info", lambda c: arg(c, "kind") == "headphones")]),
    ("поставь таймер на полтора часа", [("timer", lambda c: (n(arg(c, "hours")) * 60 + n(arg(c, "minutes"))) == 90)]),
    ("напомни через 20 минут выключить плиту", [("reminder", lambda c: arg(c, "in_minutes") == 20 and "плит" in low(arg(c, "text")))]),
    ("напомни в 18:00 позвонить маме", [("reminder", lambda c: arg(c, "at") == "18:00" and "мам" in low(arg(c, "text")))]),
    ("разбуди меня в 7:30", [("alarm", lambda c: low(arg(c, "time")).lstrip("0") == "7:30")]),
    ("вруби металлику", [("play_music", lambda c: "металлик" in low(arg(c, "query")) or "metallica" in low(arg(c, "query")))]),
    # вопросы — отвечает сама, хотя бы примерно; в Claude отправляет только «морковь»
    ("напиши скрипт на питоне для разбора логов nginx", "chat"),
    ("какие главные новости в мире сегодня", ("chat", [("web_search", lambda c: "новост" in low(arg(c, "query")))])),
    ("что такое чёрная дыра, коротко", "chat"),
    ("сколько стоит примерно хороший пк", "chat"),
    ("напиши стих про осень", "chat"),
]


VOICE = "--voice" in sys.argv
AREAS = {"screenshot": "full", "screenshot_region": "region", "screenshot_frame": "pretty", "lens": "lens"}


def internal(name, a):
    """Вызов укрупнённого инструмента (public.py) → прежнее мелкое имя: ожидания ниже — в них."""
    act = a.get("action")
    if name == "toggle":
        f = a.get("feature")
        return (f, {"on": a.get("on")}) if f in ("night_light", "do_not_disturb") else ("radio", {"device": f, "on": a.get("on")})
    if name == "app":
        return ("close_app" if act == "close" else "open_app"), {"name": a.get("name")}
    if name == "web":
        return ("open_url", {"url": a["url"]}) if a.get("url") else ("web_search", {"query": a.get("query"), "site": a.get("site")})
    if name == "window" and act == "move":
        return "move_window", {"workspace": a.get("workspace")}
    if name == "screen":
        if act in AREAS:
            return "screenshot", {"area": AREAS[act]}
        if act in ("record", "stop_record"):
            return "screen_record", {"action": "start" if act == "record" else "stop"}
        return {"lock": "lock_screen", "wallpaper": "wallpaper"}.get(act, "screen"), {}
    if name == "timer" and act == "stop":
        return "cancel_timer", {}
    if name == "reminder" and a.get("alarm"):
        return "alarm", {"time": a.get("at")}
    if name == "memory":
        return ("forget", {"what": a.get("text")}) if act == "forget" else ("remember", {"fact": a.get("text")})
    return name, a


def verdict(expect, calls, text):
    if isinstance(expect, tuple):                    # несколько верных вариантов
        return any(verdict(e, calls, text) for e in expect)
    if expect.startswith("chat") if isinstance(expect, str) else False:
        needle = expect[5:]                          # «chat:ром» — ответ словами, и в нём есть «ром»
        return not calls and bool(text.strip()) and "claude" not in text.lower() and needle in text.lower()
    left = list(calls)
    for name, check in expect:
        hit = next((c for c in left if c["name"] == name and check(c)), None)
        if hit is None:
            return False
        left.remove(hit)
    return not left


async def main():
    calls = []

    async def record(name, args):
        try:
            args = json.loads(args or "{}") if isinstance(args, str) else args
        except ValueError:
            args = {}
        calls.append(dict(zip(("name", "args"), internal(name, args))))
        return Result(True, "ок")

    tmp = tempfile.TemporaryDirectory()
    mem = Memory(Path(tmp.name) / "memory.json")
    mem.add("Пользователя зовут Рома")
    patch.object(memory, "store", mem).start()
    server = LocalServer(port=8093)
    brain = LocalBrain(server)
    await server.ensure(config.load())
    try:
        async def nothing(_):
            pass
        await brain.answer("привет", False, nothing, nothing)          # прогрев: промпт и инструменты в кэш
        ok, times, fails = 0, [], []
        with patch.object(tools, "run", record):
            for text, expect in CASES:
                brain.reset()
                calls.clear()
                t = time.monotonic()
                reply = await brain.answer(text, VOICE, nothing, nothing)
                times.append(time.monotonic() - t)
                # tools.run подменён, поэтому вызовы берём из записи
                good = verdict(expect, list(calls), reply.text)
                ok += good
                if not good:
                    fails.append(f"  ✗ {text} → {calls or ''} {reply.text[:70]!r}")
        print(f"верно {ok}/{len(CASES)}, медиана {statistics.median(times):.2f} с, максимум {max(times):.2f} с")
        print("\n".join(fails))
    finally:
        await server.stop()


if __name__ == "__main__":
    asyncio.run(main())
