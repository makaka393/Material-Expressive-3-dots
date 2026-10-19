"""Основа инструментов: описание, результат и запуск команд."""
import asyncio
import json
import os
import shlex
from pathlib import Path
from dataclasses import dataclass
from typing import Awaitable, Callable


@dataclass
class Result:
    ok: bool
    show: str                   # коротко для острова и лаунчера: «Следующий трек»
    say: str | None = None      # что произнести голосом; None — молча (смену трека и так слышно)
    data: str | None = None     # прочитать модели и ответить по нему (выдача поиска); иначе ей — show


@dataclass
class Tool:
    name: str
    description: str
    params: dict                # JSON Schema свойств
    required: list
    handler: Callable[[dict], Awaitable[Result]] | None
    visible: bool = True        # показывать ли модели (скрытые вызываются через укрупнённые — public.py)


def session_env() -> dict:
    """Окружение для команд с переменными сессии Hyprland. Служба стартует при входе вместе с Hyprland — раньше,
    чем он передаёт их systemd («HYPRLAND_INSTANCE_SIGNATURE not set!»), а после перезапуска Hyprland они
    устаревают. Поэтому сокеты ищем сами: самый свежий $XDG_RUNTIME_DIR/hypr/*/.socket.sock и wayland-N."""
    env = dict(os.environ)
    run = Path(env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    sig = env.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig or not (run / "hypr" / sig / ".socket.sock").exists():
        live = sorted((d for d in (run / "hypr").glob("*") if (d / ".socket.sock").exists()),
                      key=lambda d: d.stat().st_mtime, reverse=True)
        if live:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = live[0].name
    if not env.get("WAYLAND_DISPLAY") or not (run / env["WAYLAND_DISPLAY"]).exists():
        socks = sorted((w for w in run.glob("wayland-*") if not w.name.endswith(".lock")),
                       key=lambda w: w.stat().st_mtime, reverse=True)
        if socks:
            env["WAYLAND_DISPLAY"] = socks[0].name
    env.setdefault("XDG_RUNTIME_DIR", str(run))
    return env


async def sh(*argv: str, timeout: float = 5) -> str:
    """Команда без shell; stdout. Ненулевой код или таймаут — RuntimeError."""
    proc = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                                                env=session_env())
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


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


async def hypr(lua: str) -> str:
    """Диспетчер Hyprland. Конфиг на Lua — и dispatch принимает Lua: hl.dsp.focus({ workspace = 2 })."""
    return await sh("hyprctl", "dispatch", lua)


async def clients() -> list:
    return json.loads(await sh("hyprctl", "clients", "-j") or "[]")


async def launch(*argv: str) -> str:
    """Запустить программу руками Hyprland, а не службы: процессы службы systemd убивает при её перезапуске."""
    return await hypr(f"hl.dsp.exec_cmd({lua_str(' '.join(shlex.quote(a) for a in argv))})")


async def active() -> dict:
    return json.loads(await sh("hyprctl", "activewindow", "-j") or "{}") or {}


async def workspace_id():
    return (json.loads(await sh("hyprctl", "activeworkspace", "-j") or "{}") or {}).get("id")


async def focus(address: str) -> bool:
    """Фокус на окно по адресу; True — оно и правда стало активным."""
    await hypr(f'hl.dsp.focus({{ window = "address:{address}" }})')
    return (await active()).get("address") == address


async def on_window(address: str, lua: str):
    """Диспетчер для конкретного окна. Ключ window = … Lua-диспетчеры Hyprland молча пропускают и бьют
    по активному окну (так закрылся браузер пользователя), поэтому: фокус, проверка, потом действие."""
    if not await focus(address):
        raise RuntimeError("не получилось переключиться на окно")
    await hypr(lua)
