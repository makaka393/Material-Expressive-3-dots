"""Питание — только с подтверждением: инструмент спрашивает «Выключить компьютер? Скажи «да»»,
а выполняет служба, когда следующая фраза в течение 20 с — «да» (power.confirm)."""
import re
import time

from . import base, register
from .base import Result, Tool

WINDOW = 20              # с на ответ
ACTIONS = {"shutdown": ("Выключить компьютер?", "poweroff", "Выключаю"),
           "reboot": ("Перезагрузить компьютер?", "reboot", "Перезагружаю"),
           "suspend": ("Усыпить компьютер?", "suspend", "Усыпляю")}
YES = {"да", "давай", "ага", "угу", "конечно", "подтверждаю", "выключай", "перезагружай", "усыпляй", "ок", "окей"}
NO = {"нет", "не", "отмена", "отмени", "стоп", "отбой"}
PENDING = None           # (действие, до какого времени ждать ответ)


def pending():
    return PENDING[0] if PENDING and time.monotonic() <= PENDING[1] else None


async def power(args):
    global PENDING
    action = args["action"]
    PENDING = (action, time.monotonic() + WINDOW)
    q = ACTIONS[action][0]
    return Result(True, q, f"{q} Скажи «да».")


async def confirm(text):
    """Ответ на вопрос о питании: Result — ответ; None — вопроса нет (или протух), фраза обычная."""
    global PENDING
    if not PENDING:
        return None
    action, deadline = PENDING
    PENDING = None
    if time.monotonic() > deadline:
        return None
    first = (re.sub(r"[^\w\s]", " ", text.lower()).split() or [""])[0]
    if first in YES:
        _, cmd, done = ACTIONS[action]
        await base.sh("systemctl", cmd)
        return Result(True, done, done + ".")
    if first in NO:
        return Result(True, "Отменил", "Отменил.")
    return None


register(Tool("power", "Выключить, перезагрузить или усыпить компьютер — только если явно просят. Сам спросит подтверждение",
              {"action": {"type": "string", "enum": list(ACTIONS)}}, ["action"], power))
