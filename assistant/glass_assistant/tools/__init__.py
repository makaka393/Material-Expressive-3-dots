"""Инструменты ассистента: одни и те же для локальной модели (формат OpenAI) и Claude.

Каждый модуль рядом регистрирует свои инструменты через register(). Модель зовёт инструмент
по имени — run() проверяет аргументы, выполняет и возвращает Result; ошибки не вылетают наружу.
"""
import asyncio
import json
import re

from .base import Result, Tool

TOOLS: dict[str, Tool] = {}
TIMEOUT = 5


def register(tool: Tool) -> Tool:
    TOOLS[tool.name] = tool
    return tool


def _schema(t: Tool) -> dict:
    return {"type": "object", "properties": t.params, "required": t.required}


def openai_tools() -> list[dict]:
    return [{"type": "function", "function": {"name": t.name, "description": t.description, "parameters": _schema(t)}}
            for t in TOOLS.values()]


def anthropic_tools() -> list[dict]:
    return [{"name": t.name, "description": t.description, "input_schema": _schema(t)}
            for t in TOOLS.values() if t.claude]


def _coerce(value, schema):
    """Маленькие модели шлют числа строками: "40" → 40, "true" → True."""
    kind = schema.get("type")
    if kind == "integer" and isinstance(value, str):
        if not re.fullmatch(r"[+-]?\d+", value.strip()):
            raise ValueError(f"не число: {value}")
        return int(value)
    if kind == "integer" and isinstance(value, float):
        return round(value)
    if kind == "boolean" and isinstance(value, str):
        if value.lower() not in ("true", "false"):
            raise ValueError(f"не да/нет: {value}")
        return value.lower() == "true"
    return value


async def run(name: str, args) -> Result:
    tool = TOOLS.get(name)
    if tool is None:
        return Result(False, f"Не получилось: нет инструмента {name}")
    try:
        if isinstance(args, str):
            args = json.loads(args or "{}")
        args = {k: _coerce(v, tool.params[k]) for k, v in (args or {}).items() if k in tool.params}
    except (ValueError, TypeError, AttributeError) as e:
        return Result(False, f"Не получилось: непонятные параметры ({e})")
    if tool.handler is None:
        return Result(True, "")
    try:
        return await asyncio.wait_for(tool.handler(args), TIMEOUT)
    except asyncio.TimeoutError:
        return Result(False, "Не получилось: не успел")
    except Exception as e:
        return Result(False, f"Не получилось: {e}")


from . import media, system  # noqa: E402,F401 — регистрируют свои инструменты
