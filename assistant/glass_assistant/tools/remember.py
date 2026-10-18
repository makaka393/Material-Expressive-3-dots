"""Запомнить и забыть — долгая память ассистента (memory.py)."""
from .. import memory
from . import register
from .base import Result, Tool


async def remember(args):
    fact = args["fact"].strip()
    memory.store.add(fact)
    return Result(True, f"Запомнил: {fact}", "Запомнил.")


async def forget(args):
    gone = memory.store.forget(args["what"])
    if not gone:
        return Result(False, "Такого не помню", "Такого не помню.")
    return Result(True, "Забыл: " + "; ".join(gone), "Забыл.")


STR = {"type": "string"}
register(Tool("remember", "Запомнить надолго факт о пользователе — только когда просят «запомни …». fact — "
              "коротко, от третьего лица: «Пользователя зовут Рома», «Любит Linkin Park»", {"fact": STR}, ["fact"], remember))
register(Tool("forget", "Забыть то, что запомнил, — когда просят «забудь …»; what — о чём («про машину», «всё»)",
              {"what": STR}, ["what"], forget))
