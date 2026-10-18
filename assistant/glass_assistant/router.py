"""Куда отправить фразу: локальной модели или Claude.

По умолчанию — локальной. «Морковка, …» в начале фразы (слова — claude_words в настройках)
отправляет эту одну фразу в Claude; одно слово без вопроса — прошлый вопрос локальной модели.
"""
import re
from dataclasses import dataclass

# что можно сказать перед словом: «эй, морковка …»; иначе «купи морковку» ушло бы в Claude
FILLERS = {"эй", "окей", "ок", "слушай"}
QUOTES = "«»\"„“”'"                  # Whisper иногда берёт фразу в кавычки


@dataclass
class Route:
    brain: str         # local | claude
    text: str          # вопрос без ключевого слова
    escalated: bool    # одно слово без вопроса — переспросить прошлый вопрос у Claude


def strip_word(text: str, words, lead=None) -> str | None:
    """Если одно из слов — в первых трёх словах фразы, остаток после него ("" — только слово), иначе None.
    Слово узнаётся по началу: «морковк…» — и падежи, и огрехи распознавания. lead — какие слова
    могут стоять перед ним (None — любые)."""
    t = re.sub(r"[^\w\s-]", " ", text.lower()).split()
    for w in words:
        w = w.lower()
        stem = w[:max(4, len(w) - 1)]
        for i in range(min(3, len(t))):
            if t[i].startswith(stem):
                tail = text.split(None, i + 1)
                return tail[i + 1].lstrip(" ,.!?" + QUOTES).rstrip(" " + QUOTES) if len(tail) > i + 1 else ""
            if lead is not None and t[i] not in lead:
                break
    return None


# Слово-активатор сравнивается по звучанию: Whisper пишет «обс» как «Опс», «обси» — «Общи», «ОПСИ»,
# «Обсе», «обсик» — «а псих». Звонкие → глухие, безударные о → а, е/ы/э → и, шипящие → с.
LATIN = str.maketrans({"a": "а", "b": "б", "c": "к", "d": "д", "e": "е", "f": "ф", "g": "г", "h": "х", "i": "и",
                       "j": "й", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р", "s": "с",
                       "t": "т", "u": "у", "v": "в", "y": "ы", "z": "з"})
SOUND = str.maketrans({"о": "а", "ё": "и", "е": "и", "э": "и", "ы": "и", "я": "а", "ю": "у", "й": "и", "б": "п",
                       "в": "ф", "г": "к", "д": "т", "ж": "с", "з": "с", "ш": "с", "щ": "с", "х": "к",
                       "ь": None, "ъ": None})


def sound(word: str) -> str:
    return re.sub(r"[^\w]", "", word.lower()).translate(LATIN).translate(SOUND)


def wake(text: str, words) -> str | None:
    """Если фраза начинается со слова-активатора — остаток ("" — только оно), иначе None. Длинные слова
    («обсидиан») — по началу: «обсидианчик»; короткие («обс», «обси») — только целиком: иначе «обсудим»."""
    keys = [sound(w) for w in words]
    toks = text.split()
    for i in range(min(3, len(toks))):
        cands = [(sound(toks[i]), 1)]
        if sound(toks[i]) in ("а", "у") and i + 1 < len(toks):
            cands.append((sound(toks[i]) + sound(toks[i + 1]), 2))       # «а псих» — это «обсик»
        for k, n in cands:
            if any(k == w or len(w) >= 6 and k.startswith(w[:6]) for w in keys):
                tail = text.split(None, i + n)
                return tail[i + n].lstrip(" ,.!?" + QUOTES).rstrip(" " + QUOTES) if len(tail) > i + n else ""
        if sound(toks[i]) not in {sound(f) for f in FILLERS}:
            break
    return None


def route(text: str, cfg: dict, to: str | None = None, last: str | None = None) -> Route:
    backend = cfg.get("backend", "auto")
    if backend == "local":
        return Route("local", text, False)
    rest = strip_word(text, cfg.get("claude_words") or [], lead=FILLERS)
    if rest is None:
        brain = "claude" if to == "claude" or backend == "claude" else "local"
        return Route(brain, text, False)
    if rest == "":
        return Route("claude", last or "", True)
    return Route("claude", rest, False)
