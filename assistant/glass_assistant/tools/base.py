"""Основа инструментов: описание, результат и запуск команд."""
import asyncio
from dataclasses import dataclass
from typing import Awaitable, Callable


@dataclass
class Result:
    ok: bool
    show: str                   # коротко для острова и лаунчера: «Следующий трек»
    say: str | None = None      # что произнести голосом; None — молча (смену трека и так слышно)


@dataclass
class Tool:
    name: str
    description: str
    params: dict                # JSON Schema свойств
    required: list
    handler: Callable[[dict], Awaitable[Result]] | None
    claude: bool = True         # давать ли инструмент Claude


async def sh(*argv: str, timeout: float = 5) -> str:
    """Команда без shell; stdout. Ненулевой код или таймаут — RuntimeError."""
    proc = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError(f"{argv[0]} не ответил")
    if proc.returncode != 0:
        raise RuntimeError((err or out).decode(errors="replace").strip() or f"{argv[0]}: код {proc.returncode}")
    return out.decode(errors="replace").strip()


async def qs(target: str, fn: str, *args) -> str:
    """Вызов IPC оболочки: qs ipc -c glass call <target> <fn> …"""
    return await sh("qs", "ipc", "-c", "glass", "call", target, fn, *map(str, args))
