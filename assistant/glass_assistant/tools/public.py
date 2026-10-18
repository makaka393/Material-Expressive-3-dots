"""Инструменты, которые видит модель: похожие действия собраны в один инструмент с action.

27 мелких инструментов (8 тыс. знаков схем) маленькая модель путала: отвечала «Начинаю запись экрана»
без вызова, переспрашивала город для погоды — eval 60/78. Мелкие остаются (их вызывают эти и тесты),
но модели не показываются.
"""
from . import TOOLS, apps, register, remember, shell, system, timers, windows
from .base import Result, Tool

STR = {"type": "string"}
INT = {"type": "integer"}
BOOL = {"type": "boolean"}


def _enum(*v):
    return {"type": "string", "enum": list(v)}


async def toggle(args):
    feature, on = args["feature"], args["on"]
    if feature == "night_light":
        return await system.night_light({"on": on})
    if feature == "do_not_disturb":
        return await system.do_not_disturb({"on": on})
    return await shell.radio({"device": feature, "on": on})


async def app(args):
    return await (apps.close_app(args) if args.get("action") == "close" else apps.open_app(args))


async def web(args):
    if args.get("url"):
        return await apps.open_url({"url": args["url"]})
    if args.get("query"):
        return await apps.web_search({"query": args["query"], "site": args.get("site")})
    return Result(False, "Не сказано, что открыть", "Не сказано, что открыть.")


async def window(args):
    if args.get("action") == "move":
        return await windows.move_window({"workspace": args.get("workspace") or 1, "app": args.get("app")})
    return await windows.window(args)


SCREEN = {"screenshot": lambda: shell.screenshot({"area": "full"}),
          "screenshot_region": lambda: shell.screenshot({"area": "region"}),
          "screenshot_frame": lambda: shell.screenshot({"area": "pretty"}),
          "lens": lambda: shell.screenshot({"area": "lens"}),
          "record": lambda: shell.screen_record({"action": "start"}),
          "stop_record": lambda: shell.screen_record({"action": "stop"}),
          "lock": lambda: shell.lock_screen({}),
          "wallpaper": lambda: shell.wallpaper({})}


async def screen(args):
    return await SCREEN[args["action"]]()


async def timer(args):
    return await (timers.cancel_timer(args) if args.get("action") == "stop" else timers.timer(args))


async def reminder(args):
    if args.get("alarm"):
        return await timers.alarm({"time": args.get("at") or ""})
    return await timers.reminder({"text": args.get("text") or "напоминание", "in_minutes": args.get("in_minutes"),
                                  "at": args.get("at")})


async def memory(args):
    if args.get("action") == "forget":
        return await remember.forget({"what": args.get("text") or ""})
    return await remember.remember({"fact": args.get("text") or ""})


register(Tool("toggle", "Включить или выключить: ночной режим (тёплый экран), «не беспокоить», Wi-Fi, Bluetooth",
              {"feature": _enum("night_light", "do_not_disturb", "wifi", "bluetooth"), "on": BOOL}, ["feature", "on"], toggle))
register(Tool("app", "Открыть или закрыть приложение (браузер, телега, дискорд, стим, спотифай, терминал, проводник, "
              "настройки…) или известный сайт (гитхаб, ютуб). Уже открытое — покажет",
              {"action": _enum("open", "close"), "name": STR}, ["action", "name"], app))
register(Tool("web", "Открыть сайт по адресу (url) или найти в интернете (query) — только когда просят найти, загуглить",
              {"url": STR, "query": STR, "site": _enum("google", "youtube", "wikipedia", "maps", "github")}, [], web))
register(Tool("window", "Окно: закрыть, во весь экран, плавающее, закрепить, перенести на рабочий стол (move + workspace). "
              "Без app — активное окно, не переспрашивай",
              {"action": _enum("close", "fullscreen", "float", "pin", "move"), "workspace": INT, "app": STR}, ["action"], window))
register(Tool("screen", "Экран: screenshot — скриншот всего экрана, screenshot_region — области, screenshot_frame — области "
              "в рамке, lens — область в Google Lens, record / stop_record — запись экрана, lock — заблокировать, "
              "wallpaper — сменить обои", {"action": _enum(*SCREEN)}, ["action"], screen))
register(Tool("timer", "Таймер: start — длительность частями, как сказано («полтора часа» = hours 1, minutes 30), stop — "
              "остановить", {"action": _enum("start", "stop"), "hours": INT, "minutes": INT, "seconds": INT, "label": STR},
              [], timer))
register(Tool("reminder", "Напомнить: text — о чём, через in_minutes минут или в at (HH:MM). alarm=true — будильник "
              "(«разбуди в 7:30» → at 07:30)", {"text": STR, "in_minutes": INT, "at": STR, "alarm": BOOL}, [], reminder))
register(Tool("memory", "Долгая память: remember — только когда явно говорят «запомни …» (text коротко, от третьего лица: "
              "«Любит Metallica»); forget — забыть, когда просят «забудь …» (text — о чём)",
              {"action": _enum("remember", "forget"), "text": STR}, ["action", "text"], memory))

# мелкие — только через укрупнённые
for name in ("night_light", "do_not_disturb", "radio", "open_app", "close_app", "open_url", "web_search", "move_window",
             "screenshot", "screen_record", "lock_screen", "wallpaper", "cancel_timer", "alarm", "remember", "forget"):
    TOOLS[name].visible = False
