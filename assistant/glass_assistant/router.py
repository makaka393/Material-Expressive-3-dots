"""Куда отправить фразу: локальной модели или Claude.

По умолчанию — локальной. «Морковка, …» в начале фразы (слова — claude_words в настройках)
отправляет эту одну фразу в Claude; одно слово без вопроса — прошлый вопрос локальной модели.
"""
import re
from dataclasses import dataclass

# что можно сказать перед словом: «эй, морковка …»; иначе «купи морковку» ушло бы в Claude
FILLERS = {"эй", "окей", "ок", "слушай"}


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
                return tail[i + 1].lstrip(" ,.!?").rstrip() if len(tail) > i + 1 else ""
            if lead is not None and t[i] not in lead:
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
