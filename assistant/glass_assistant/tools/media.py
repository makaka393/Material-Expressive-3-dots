"""Плеер: то, что уже играет (любой MPRIS через playerctl), и музыка по названию в Spotify."""
import asyncio
import os
import time
from urllib.parse import quote

import httpx2

from . import base, register
from .base import Result, Tool

WAIT = 10          # с — ждать, пока запущенный Spotify появится в MPRIS

SIMPLE = {"play": ("play", "Играет"), "pause": ("pause", "Пауза"), "toggle": ("play-pause", "Пауза/продолжить"),
          "next": ("next", "Следующий трек"), "previous": ("previous", "Предыдущий трек")}


async def media(args):
    action, secs = args.get("action"), int(args.get("seconds") or 10)
    if action == "seek_forward":
        argv, show = ("position", f"{secs}+"), f"Вперёд на {secs} с"
    elif action == "seek_back":
        argv, show = ("position", f"{secs}-"), f"Назад на {secs} с"
    elif action in SIMPLE:
        argv, show = (SIMPLE[action][0],), SIMPLE[action][1]
    else:
        return Result(False, f"Не получилось: непонятное действие {action}")
    try:
        await base.sh("playerctl", *argv)
    except RuntimeError as e:
        if "No players" in str(e):
            return Result(False, "Не получилось: плеер не запущен")
        raise
    return Result(True, show)


register(Tool(
    "media",
    "Управление тем, что уже играет: пауза, продолжить («включи музыку» без названия — play), "
    "следующий/предыдущий трек («следующую», «скип»), перемотка",
    {"action": {"type": "string", "enum": ["play", "pause", "toggle", "next", "previous", "seek_forward", "seek_back"]},
     "seconds": {"type": "integer", "description": "для перемотки"}},
    ["action"], media))


# ── музыка по названию: поиск по Spotify Web API (ключи приложения, без входа пользователя) и
#    запуск в Spotify через MPRIS OpenUri. Ключи: developer.spotify.com → Create app →
#    SPOTIFY_CLIENT_ID и SPOTIFY_CLIENT_SECRET в ~/.config/glass/assistant.env
_tok = None        # (токен, когда истекает)


async def _post_token(cid, secret):
    async with httpx2.AsyncClient(timeout=6) as http:
        r = await http.post("https://accounts.spotify.com/api/token", data={"grant_type": "client_credentials"},
                            auth=(cid, secret))
        r.raise_for_status()
        return r.json()


async def token():
    global _tok
    if _tok is None or time.monotonic() > _tok[1]:
        d = await _post_token(os.environ["SPOTIFY_CLIENT_ID"], os.environ["SPOTIFY_CLIENT_SECRET"])
        _tok = (d["access_token"], time.monotonic() + d.get("expires_in", 3600) - 60)
    return _tok[0]


async def search(query, kind):
    """Первый результат поиска: {"uri", "name", "by"} или None."""
    async with httpx2.AsyncClient(timeout=6) as http:
        r = await http.get(f"https://api.spotify.com/v1/search?q={quote(query)}&type={kind}&limit=1",
                           headers={"Authorization": f"Bearer {await token()}"})
        r.raise_for_status()
        items = r.json().get(kind + "s", {}).get("items") or []
    if not items or not items[0]:
        return None
    it = items[0]
    by = ", ".join(a["name"] for a in it.get("artists", [])) or (it.get("owner") or {}).get("display_name", "")
    return {"uri": it["uri"], "name": it["name"], "by": by}


async def _spotify_running():
    if "spotify" in (await base.sh("playerctl", "-l")).split():
        return True
    await base.launch("gtk-launch", "spotify")
    for _ in range(int(WAIT / 0.25) or 1):
        await asyncio.sleep(min(0.25, WAIT))
        if "spotify" in (await base.sh("playerctl", "-l")).split():
            await asyncio.sleep(1.5)               # MPRIS появился раньше, чем Spotify готов принять трек
            return True
    return False


async def play_music(args):
    query = args["query"].strip()
    kind = {"artist": "artist", "album": "album", "playlist": "playlist"}.get(args.get("kind"), "track")
    if not (os.environ.get("SPOTIFY_CLIENT_ID") and os.environ.get("SPOTIFY_CLIENT_SECRET")):
        await base.launch("xdg-open", f"spotify:search:{query}")
        return Result(True, f"Открыл поиск «{query}» в Spotify",
                      "Открыл поиск в Spotify. Чтобы включалось сразу, нужен ключ Spotify.")
    found = await search(query, kind)
    if not found:
        return Result(False, f"Не нашёл «{query}» в Spotify", f"Не нашёл «{query}» в Spotify.")
    if not await _spotify_running():
        return Result(False, "Spotify не запустился", "Spotify не запустился.")
    await base.sh("playerctl", "-p", "spotify", "open", found["uri"])
    return Result(True, f"Включаю {found['name']}" + (f" — {found['by']}" if found["by"] else ""))


register(Tool(
    "play_music",
    "Найти и включить в Spotify конкретное: трек, исполнителя, альбом, плейлист или жанр («включи Linkin Park», "
    "«поставь Numb»). Без названия не вызывать — это media",
    {"query": {"type": "string"}, "kind": {"type": "string", "enum": ["track", "artist", "album", "playlist", "any"]}},
    ["query"], play_music))
