"""glass-assistant: служба (serve) и короткие команды к ней.

  python -m glass_assistant serve            запустить службу (обычно — systemd --user)
  python -m glass_assistant ask "вопрос"     спросить текстом и напечатать ответ («морковь, …» — у Claude)
  python -m glass_assistant claude "вопрос"  спросить сразу у Claude
  python -m glass_assistant listen           выслушать голосом (второй раз — стоп)
  python -m glass_assistant say "текст"      произнести
  python -m glass_assistant warm | unload    загрузить локальную модель заранее | выгрузить
  python -m glass_assistant stop | reset | status
"""
import asyncio
import json
import sys

from . import config


async def client(cmd: dict, wait: bool):
    reader, writer = await asyncio.open_unix_connection(str(config.SOCKET))
    writer.write((json.dumps(cmd, ensure_ascii=False) + "\n").encode())
    await writer.drain()
    if not wait:
        # дождаться первого события: служба при подключении пишет клиенту состояние, и если клиент уже
        # ушёл, запись рвёт соединение — непрочитанная команда терялась (`unload` не выгружал модель)
        try:
            await asyncio.wait_for(reader.readline(), 2)
        except asyncio.TimeoutError:
            pass
        writer.close()
        await writer.wait_closed()
        return 0
    asked = False
    while line := await reader.readline():
        ev = json.loads(line)
        if ev["ev"] == "state" and ev["state"] != "idle":
            asked = True
        elif ev["ev"] == "action":
            print(f"⚙ {ev['show']}", flush=True)
        elif ev["ev"] == "delta":
            print(ev["text"], end="", flush=True)
        elif ev["ev"] == "heard":
            print(f"» {ev['text']}", flush=True)
        elif ev["ev"] == "done":
            print(f"\n[{ev['backend']}]", flush=True)
        elif ev["ev"] == "error":
            print(f"\nошибка: {ev['text']}", file=sys.stderr, flush=True)
            return 1
        if ev["ev"] == "state" and ev["state"] == "idle" and asked:
            break
    writer.close()
    return 0


def main():
    args = sys.argv[1:] or ["serve"]
    op, rest = args[0], " ".join(args[1:])
    if op == "serve":
        from .daemon import Daemon
        asyncio.run(Daemon().serve())
        return
    cmds = {"ask": ({"cmd": "ask", "text": rest, "speak": False}, True),
            "claude": ({"cmd": "ask", "text": rest, "speak": False, "to": "claude"}, True),
            "listen": ({"cmd": "listen"}, True),
            "warm": ({"cmd": "warm"}, False),
            "unload": ({"cmd": "unload"}, False),
            "say": ({"cmd": "say", "text": rest}, False),
            "stop": ({"cmd": "stop"}, False),
            "reset": ({"cmd": "reset"}, False),
            "status": ({"cmd": "status"}, False)}
    if op not in cmds:
        print(__doc__)
        sys.exit(2)
    try:
        sys.exit(asyncio.run(client(*cmds[op])))
    except (ConnectionRefusedError, FileNotFoundError):
        print("служба не запущена: systemctl --user start glass-assistant", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
