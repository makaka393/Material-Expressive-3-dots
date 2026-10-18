"""Оценка локальной модели на живом llama-server: верно ли выбирает действия и как быстро.

Не входит в unittest (имя без test_): нужна видеокарта и ~3,3 ГБ видеопамяти. Действия не выполняются —
инструменты подменены записью вызовов. Запуск из assistant/:
    python -m tests.eval_local            вопросы как из лаунчера
    python -m tests.eval_local --voice    как голосом (с указанием про озвучку)
"""
import asyncio
import json
import statistics
import sys
import time
from unittest.mock import patch

from glass_assistant import config, tools
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
    ("открой гитхаб", [("open_url", lambda c: "github" in low(arg(c, "url")))]),
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
    # инструментов ещё нет — сказать «не умею», а не хвататься за чужой
    ("выключи компьютер", "chat"),
    ("перезагрузи комп", "chat"),
    ("заблокируй экран", "chat"),
    # вопросы — отвечает сама, хотя бы примерно; в Claude отправляет только «морковь»
    ("напиши скрипт на питоне для разбора логов nginx", "chat"),
    ("какие главные новости в мире сегодня", "chat"),
    ("что такое чёрная дыра, коротко", "chat"),
    ("сколько стоит примерно хороший пк", "chat"),
    ("напиши стих про осень", "chat"),
]


VOICE = "--voice" in sys.argv


def verdict(expect, calls, text):
    if expect == "chat":
        return not calls and bool(text.strip()) and "claude" not in text.lower()
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
        calls.append({"name": name, "args": args})
        return Result(True, "ок")

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
