"""Приложения и сайты: открыть (или показать уже открытое), закрыть, сайт, поиск."""
import configparser
import difflib
import html
import os
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, quote_plus

import httpx2

from . import base, register
from .base import Result, Tool

HOME = Path.home()
DIRS = [HOME / ".local/share/applications", Path("/usr/local/share/applications"), Path("/usr/share/applications"),
        HOME / ".local/share/flatpak/exports/share/applications", Path("/var/lib/flatpak/exports/share/applications")]

# как называют вслух → что искать среди приложений (по началу слова: «телегу», «телеги»)
ALIASES = {"телег": "telegram", "тг": "telegram", "стим": "steam", "спотик": "spotify", "музык": "spotify",
           "терминал": "kitty", "консол": "kitty", "проводник": "file manager", "файл": "file manager", "вк": "vk",
           "ютуб": "youtube", "обс": "obs"}
BROWSER = ("браузер", "browser", "интернет")
SETTINGS = ("настройки", "настройки оболочки")
LAT = str.maketrans({"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z",
                     "и": "i", "й": "j", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
                     "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch",
                     "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"})
# приложения нет, а сайт известный: «открой гитхаб» модель отдаёт в open_app
SITE_NAMES = {"github": "github.com", "гитхаб": "github.com", "youtube": "youtube.com", "ютуб": "youtube.com",
              "вк": "vk.com", "вконтакте": "vk.com", "twitch": "twitch.tv", "твич": "twitch.tv",
              "reddit": "reddit.com", "реддит": "reddit.com", "кинопоиск": "kinopoisk.ru", "gmail": "mail.google.com",
              "почта": "mail.google.com", "chatgpt": "chatgpt.com", "чатгпт": "chatgpt.com"}
SITES = {"google": "https://www.google.com/search?q=", "youtube": "https://www.youtube.com/results?search_query=",
         "wikipedia": "https://ru.wikipedia.org/w/index.php?search=", "maps": "https://www.google.com/maps/search/",
         "github": "https://github.com/search?q="}


@dataclass
class Entry:
    id: str          # имя файла без .desktop — его понимает gtk-launch
    name: str
    wm_class: str
    exec: str
    words: str       # всё, по чему искать: имена, описания, ключевые слова


def entries() -> list:
    seen, out = set(), []
    for d in DIRS:
        for f in sorted(Path(d).glob("*.desktop")) if Path(d).is_dir() else []:
            if f.name in seen:
                continue
            seen.add(f.name)
            p = configparser.RawConfigParser(strict=False, interpolation=None)
            p.optionxform = str
            try:
                p.read(f, encoding="utf-8")
                e = p["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            if e.get("Type", "Application") != "Application" or e.get("NoDisplay") == "true" or e.get("Hidden") == "true":
                continue
            exe = os.path.basename((e.get("Exec") or "").split()[0]) if e.get("Exec") else ""
            words = " ".join(e.get(k, "") for k in ("Name", "Name[ru]", "GenericName", "GenericName[ru]", "Keywords",
                                                    "Keywords[ru]", "StartupWMClass")).replace(";", " ")
            out.append(Entry(f.name[:-8], e.get("Name", f.name[:-8]), e.get("StartupWMClass", ""), exe,
                             f"{words} {exe} {f.name[:-8]}".lower()))
    return out


def _norm(name: str) -> str:
    name = re.sub(r"[^\w\s-]", " ", name.lower()).strip()
    first = name.split()[0] if name else ""
    for k, v in ALIASES.items():
        # короткие прозвища («тг», «вк») — только целиком; длинные — по началу слова («файловый», «телегу»)
        if first == k or len(k) >= 4 and first.startswith(k):
            return v
    return name


def find(name: str) -> Entry | None:
    q = _norm(name)
    if not q:
        return None
    best, score = None, 0.0
    for e in entries():
        ws = set(re.split(r"[\s.\-_]+", e.words)) - {""}
        if q in (e.id.lower(), e.name.lower()):
            s = 1.0
        elif q in e.words and (q in ws or len(q) >= 5):
            s = 0.9                                   # «файловый менеджер», «медиаплеер»
        else:
            lat = q.translate(LAT)                    # «телеграм» → telegram, «влц» → vlc
            s = max([difflib.SequenceMatcher(None, lat, w).ratio() for w in ws] + [0]) * 0.85
            if lat in ws:
                s = 0.95
        if s > score:
            best, score = e, s
    return best if score >= 0.64 else None


def _windows(e: Entry, wins: list) -> list:
    keys = {k.lower() for k in (e.wm_class, e.id, e.exec, e.id.split(".")[-1]) if k}
    return [w for w in wins if (w.get("class") or "").lower() in keys]


async def open_app(args):
    name = args["name"].strip()
    if name.lower() in SETTINGS:
        await base.qs("settings", "open")
        return Result(True, "Открываю настройки")
    e = None
    if name.lower() in BROWSER:
        default = (await base.sh("xdg-settings", "get", "default-web-browser")).strip()
        e = next((x for x in entries() if x.id == default.removesuffix(".desktop")), None)
    e = e or find(name)
    if e is None:
        site = SITE_NAMES.get(name.lower())
        if site:
            await base.launch("xdg-open", "https://" + site)
            return Result(True, f"Открываю {site}")
        return Result(False, f"Не нашёл приложение «{name}»", f"Не нашёл приложение «{name}».")
    wins = _windows(e, await base.clients())
    if wins:
        await base.hypr(f'hl.dsp.focus({{ window = "address:{wins[0]["address"]}" }})')
        return Result(True, f"Показываю {e.name}")
    await base.launch("gtk-launch", e.id)
    return Result(True, f"Открываю {e.name}")


async def close_app(args):
    name = args["name"].strip()
    e = find(name)
    if e is None:
        return Result(False, f"Не нашёл приложение «{name}»", f"Не нашёл приложение «{name}».")
    wins = _windows(e, await base.clients())
    if not wins:
        return Result(False, f"Окна «{e.name}» нет", f"Окна «{e.name}» нет.")
    here = await base.workspace_id()
    try:
        for w in wins:
            await base.on_window(w["address"], "hl.dsp.window.close()")
    finally:
        if here is not None:
            await base.hypr(f"hl.dsp.focus({{ workspace = {here} }})")       # остаться на своём столе
    return Result(True, f"Закрываю {e.name}")


async def open_url(args):
    url = args["url"].strip()
    if "://" not in url:
        url = "https://" + url
    if not url.startswith(("http://", "https://")):
        return Result(False, "Не получилось: открываю только сайты", "Открываю только сайты.")
    await base.launch("xdg-open", url)
    return Result(True, f"Открываю {url.split('://', 1)[1].split('/')[0]}")


async def web_search(args):
    site = args.get("site") or "google"
    base_url = SITES.get(site, SITES["google"])
    q = quote(args["query"]) if site == "maps" else quote_plus(args["query"])
    await base.launch("xdg-open", base_url + q)
    return Result(True, f"Ищу «{args['query']}»" + ("" if site == "google" else f" на {site}"))


# найти и ответить: выдача DuckDuckGo (без ключей, ~0,7 с) — модели, она отвечает по ней. Раньше поиск только
# открывался в браузере, а вслух было одно «Ищу …»
DDG = "https://html.duckduckgo.com/html/"
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"


def _clean(fragment: str) -> str:
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).split())


async def search_results(query: str, n: int = 6) -> list:
    """[(заголовок, текст)] первых результатов: DuckDuckGo, а если он не ответил (капча на частые запросы —
    код 202) — Википедия; [] — не нашлось нигде."""
    async with httpx2.AsyncClient(timeout=4, headers={"User-Agent": UA}, follow_redirects=True) as http:
        try:
            r = await http.post(DDG, data={"q": query, "kl": "ru-ru"})
            titles = re.findall(r'class="result__a"[^>]*>(.*?)</a>', r.text, re.S)
            snippets = re.findall(r'class="result__snippet"[^>]*>(.*?)</a>', r.text, re.S)
            found = [(_clean(t), _clean(sn)) for t, sn in zip(titles, snippets) if _clean(sn)][:n]
            if found:
                return found
        except httpx2.HTTPError as e:
            print("поиск DuckDuckGo:", repr(e), flush=True)
        r = await http.get("https://ru.wikipedia.org/w/api.php",
                           params={"action": "query", "generator": "search", "gsrsearch": query, "gsrlimit": 3,
                                   "prop": "extracts", "exintro": 1, "explaintext": 1, "exchars": 1200, "format": "json"},
                           headers={"User-Agent": "glass-assistant/1.0 (personal desktop assistant)"})
        pages = sorted(r.json().get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
        return [(f"Википедия: {p['title']}", " ".join(p.get("extract", "").split())[:1200]) for p in pages if p.get("extract")]


async def web_answer(args):
    q = args["query"]
    try:
        found = await search_results(q)
    except Exception as e:                       # нет сети, капча — тогда как раньше, в браузере
        print("поиск:", repr(e), flush=True)
        found = []
    if not found:
        return await web_search(args)
    lines = "\n".join(f"{i}. {t} — {sn}" for i, (t, sn) in enumerate(found, 1))
    return Result(True, f"Нашёл про «{q}»",
                  data=f"Результаты поиска «{q}» (сегодня {datetime.now():%d.%m.%Y}):\n{lines}\n"
                       "Ответь на вопрос коротко, одним-двумя предложениями, без ссылок и без «по данным сайта», "
                       "«в результатах поиска». В результатах ответа нет — ответь сам, что знаешь, и скажи, что примерно.")


STR = {"type": "string"}
register(Tool("open_app", "Открыть приложение (браузер, Telegram, Discord, Steam, Spotify, терминал, проводник, "
              "настройки…). Уже открыто — покажет его окно", {"name": STR}, ["name"], open_app))
register(Tool("close_app", "Закрыть приложение по названию (все его окна)", {"name": STR}, ["name"], close_app))
register(Tool("open_url", "Открыть сайт в браузере", {"url": STR}, ["url"], open_url))
register(Tool("web_search", "Поиск в интернете с открытием в браузере — только если явно просят найти, "
              "загуглить, поискать. На вопросы отвечай сам",
              {"query": STR, "site": {"type": "string", "enum": list(SITES)}}, ["query"], web_search))
