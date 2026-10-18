"""Таймер (его показывает и озвучивает оболочка), напоминания и будильник (планировщик службы).

Напоминания лежат в reminders.json и переживают перезапуск службы; пропущенные, пока служба
не работала, срабатывают при запуске (не старше суток).
"""
import asyncio
import json
import os
import re
import time
from datetime import datetime, timedelta
from pathlib import Path

from ..numbers import plural
from . import base, register
from .base import Result, Tool

SCHED = None             # Scheduler службы (daemon.serve); без него напоминания не работают
STALE = 86400            # с — пропущенное старше суток уже не нужно


def now():
    return datetime.now()


class Scheduler:
    def __init__(self, path, announce):
        self.path = Path(path)
        self.announce = announce             # async (текст, вид) — тост, звук, голос
        try:
            self.items = json.loads(self.path.read_text())
        except (OSError, ValueError):
            self.items = []

    def _save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.items, ensure_ascii=False, indent=1))
        os.replace(tmp, self.path)

    def add(self, when: float, text: str, kind: str):
        self.items.append({"when": when, "text": text, "kind": kind})
        self.items.sort(key=lambda i: i["when"])
        self._save()

    async def run(self, tick=1.0):
        while True:
            t = time.time()
            due = [i for i in self.items if i["when"] <= t]
            if due:
                self.items = [i for i in self.items if i["when"] > t]
                self._save()
                for i in due:
                    late = t - i["when"]
                    if late > STALE:
                        continue
                    text = i["text"]
                    if late > 60:                      # служба была выключена
                        text = ("Пропущенное напоминание: " if i["kind"] == "reminder" else "Пропущенный будильник: ") + text
                    try:
                        await self.announce(text, i["kind"])
                    except Exception as e:
                        print("напоминание:", e, flush=True)
            await asyncio.sleep(tick)


def _duration(h, m, s):
    parts = [f"{h} {plural(h, ('час', 'часа', 'часов'))}" if h else "",
             f"{m} {plural(m, ('минуту', 'минуты', 'минут'))}" if m else "",
             f"{s} {plural(s, ('секунду', 'секунды', 'секунд'))}" if s else ""]
    return " ".join(p for p in parts if p)


def _at(hhmm: str) -> datetime | None:
    """«18:00», «7:30», «18» → ближайшие такие часы: сегодня, если ещё не прошли, иначе завтра."""
    m = re.fullmatch(r"\s*(\d{1,2})(?:[:.](\d{2}))?\s*", hhmm or "")
    if not m or int(m.group(1)) > 23 or int(m.group(2) or 0) > 59:
        return None
    t = now().replace(hour=int(m.group(1)), minute=int(m.group(2) or 0), second=0, microsecond=0)
    return t if t > now() else t + timedelta(days=1)


async def timer(args):
    h, m, s = (int(args.get(k) or 0) for k in ("hours", "minutes", "seconds"))
    total = h * 3600 + m * 60 + s
    if total <= 0:
        return Result(False, "Не понял, на сколько таймер", "Не понял, на сколько таймер.")
    await base.qs("timer", "start", total, args.get("label") or "")
    return Result(True, f"Таймер на {_duration(h, m, s)}", f"Таймер на {_duration(h, m, s)}.")


async def cancel_timer(args):
    await base.qs("timer", "stop")
    return Result(True, "Таймер остановлен")


async def reminder(args):
    if SCHED is None:
        return Result(False, "Напоминания не готовы", "Напоминания не готовы.")
    if args.get("in_minutes"):
        when = now() + timedelta(minutes=int(args["in_minutes"]))
    else:
        when = _at(args.get("at"))
    if when is None:
        return Result(False, "Не понял, когда напомнить", "Не понял, когда напомнить.")
    SCHED.add(when.timestamp(), args["text"].strip(), "reminder")
    return Result(True, f"Напомню в {when:%H:%M}: {args['text']}", f"Напомню в {when:%H:%M}.")


async def alarm(args):
    if SCHED is None:
        return Result(False, "Будильник не готов", "Будильник не готов.")
    when = _at(args.get("time"))
    if when is None:
        return Result(False, "Не понял время будильника", "Не понял время будильника.")
    SCHED.add(when.timestamp(), f"Будильник, {when:%H:%M}", "alarm")
    return Result(True, f"Будильник на {when:%H:%M}", f"Будильник на {when:%H:%M}.")


INT = {"type": "integer"}
STR = {"type": "string"}
register(Tool("timer", "Таймер обратного отсчёта. Длительность — частями, как сказано: «полтора часа» = hours 1, minutes 30",
              {"hours": INT, "minutes": INT, "seconds": INT, "label": STR}, [], timer))
register(Tool("cancel_timer", "Остановить таймер", {}, [], cancel_timer))
register(Tool("reminder", "Напомнить: через in_minutes минут или в время at (HH:MM); text — о чём",
              {"text": STR, "in_minutes": INT, "at": STR}, ["text"], reminder))
register(Tool("alarm", "Будильник на время HH:MM", {"time": STR}, ["time"], alarm))
