"""Окна, рабочие столы и вкладки браузера (Hyprland, Lua-диспетчеры)."""
from . import base, register
from .apps import find, _windows
from .base import Result, Tool

ACTIONS = {"close": ("hl.dsp.window.close()", "Закрываю окно"), "fullscreen": ("hl.dsp.window.fullscreen()", "Во весь экран"),
           "float": ('hl.dsp.window.float({ action = "toggle" })', "Плавающее окно"), "pin": ("hl.dsp.window.pin()", "Закрепляю окно")}
BROWSERS = {"zen", "firefox", "librewolf", "chromium", "google-chrome", "brave-browser", "vivaldi-stable", "floorp"}
# клавиши для wtype: -M/-m — зажать/отпустить модификатор, -k — клавиша
TABS = {"next": (("ctrl",), "Tab", "Следующая вкладка"), "previous": (("ctrl", "shift"), "Tab", "Предыдущая вкладка"),
        "new": (("ctrl",), "t", "Новая вкладка"), "close": (("ctrl",), "w", "Закрываю вкладку"),
        "reopen": (("ctrl", "shift"), "t", "Возвращаю вкладку"), "back": (("alt",), "Left", "Назад"),
        "forward": (("alt",), "Right", "Вперёд"), "reload": ((), "F5", "Обновляю страницу")}


async def _target(app):
    """Адрес окна приложения или активного окна; None — нет такого окна."""
    if app:
        e = find(app)
        wins = _windows(e, await base.clients()) if e else []
        return wins[0]["address"] if wins else None
    return (await base.active()).get("address")


async def window(args):
    lua, show = ACTIONS[args["action"]]
    addr = await _target(args.get("app"))
    if not addr:
        return Result(False, "Нет такого окна", "Нет такого окна.")
    if addr == (await base.active()).get("address"):
        await base.hypr(lua)
    else:
        await base.on_window(addr, lua)
    return Result(True, show)


async def move_window(args):
    n = int(args["workspace"])
    addr = await _target(args.get("app"))
    if not addr:
        return Result(False, "Нет такого окна", "Нет такого окна.")
    lua = f"hl.dsp.window.move({{ workspace = {n} }})"
    if addr == (await base.active()).get("address"):
        await base.hypr(lua)
    else:
        await base.on_window(addr, lua)
    return Result(True, f"Переношу на {n}-й стол")


async def workspace(args):
    if args.get("number"):
        n = int(args["number"])
        await base.hypr(f"hl.dsp.focus({{ workspace = {n} }})")
        return Result(True, f"Стол {n}")
    step = "e-1" if args.get("direction") == "previous" else "e+1"
    await base.hypr(f'hl.dsp.focus({{ workspace = "{step}" }})')
    return Result(True, "Следующий стол" if step == "e+1" else "Предыдущий стол")


async def browser_tab(args):
    action = args["action"]
    if action == "number":
        mods, key, show = ("ctrl",), str(min(9, max(1, int(args.get("number") or 1)))), f"Вкладка {args.get('number')}"
    else:
        mods, key, show = TABS[action]
    act = await base.active()
    if (act.get("class") or "").lower() not in BROWSERS:
        wins = [w for w in await base.clients() if (w.get("class") or "").lower() in BROWSERS]
        if not wins:
            return Result(False, "Браузер не открыт", "Браузер не открыт.")
        if not await base.focus(wins[0]["address"]):
            return Result(False, "Не получилось переключиться на браузер", "Не получилось переключиться на браузер.")
    await base.qs("launcher", "close")               # лаунчер держит клавиатуру — клавиши ушли бы в него
    argv = [x for m in mods for x in ("-M", m)] + ["-k", key] + [x for m in reversed(mods) for x in ("-m", m)]
    await base.sh("wtype", *argv)
    return Result(True, show)


INT = {"type": "integer"}
STR = {"type": "string"}
register(Tool("window", "Действие с окном: закрыть, во весь экран, сделать плавающим, закрепить. По умолчанию — "
              "активное окно («это окно»), не переспрашивай; app — только если названо приложение", {"action": {"type": "string", "enum": list(ACTIONS)}, "app": STR},
              ["action"], window))
register(Tool("move_window", "Перенести окно (активное или приложения app) на рабочий стол", {"workspace": INT, "app": STR},
              ["workspace"], move_window))
register(Tool("workspace", "Перейти на рабочий стол: по номеру или следующий/предыдущий",
              {"number": INT, "direction": {"type": "string", "enum": ["next", "previous"]}}, [], workspace))
register(Tool("browser_tab", "Вкладки браузера: следующая, предыдущая, новая, закрыть, вернуть закрытую, назад, вперёд, "
              "обновить, по номеру", {"action": {"type": "string", "enum": list(TABS) + ["number"]}, "number": INT},
              ["action"], browser_tab))
