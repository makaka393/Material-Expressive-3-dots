"""Долгая память: факты, которые пользователь просил запомнить («запомни, что меня зовут Рома»).

Лежат в memory.json и попадают в системный промпт локальной модели и Claude. Промпт меняется, только
когда меняется память, — кэш llama-server пересчитывается лишь тогда.
"""
import json
import os
import re
import time
from pathlib import Path

from . import config

MAX = 40                 # фактов; старые вытесняются
ALL = {"всё", "все", "всю память", "всё что знаешь", "все что знаешь", "всё обо мне", "все обо мне", "всё про меня",
       "все про меня"}
SKIP = {"про", "что", "как", "меня", "мне", "мое", "моё", "мой", "моя", "мои", "это", "то", "о", "об", "обо", "забудь",
        "пожалуйста"}


def _norm(text: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", " ", text.lower().replace("ё", "е")).split())


class Memory:
    def __init__(self, path):
        self.path = Path(path)
        self._items = self._load()

    def _load(self):
        try:
            data = json.loads(self.path.read_text())
            return [{"text": str(d["text"]), "ts": d.get("ts", 0)} for d in data if isinstance(d, dict) and d.get("text")]
        except (OSError, ValueError, TypeError, KeyError):
            return []

    def _save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._items, ensure_ascii=False, indent=1))
        os.replace(tmp, self.path)

    def facts(self) -> list:
        return [d["text"] for d in self._items]

    def add(self, text: str):
        text = text.strip().rstrip(".")
        if not text or any(_norm(d["text"]) == _norm(text) for d in self._items):
            return
        self._items = (self._items + [{"text": text, "ts": int(time.time())}])[-MAX:]
        self._save()

    def forget(self, query: str) -> list:
        """Убрать факты, где встречается слово из запроса («про linkin park»); «всё» — все. → что убрано."""
        q = _norm(query)
        if q in {_norm(a) for a in ALL}:
            gone, self._items = self.facts(), []
        else:
            stems = [w[:max(4, len(w) - 2)] for w in q.split() if len(w) >= 3 and w not in SKIP]
            hit = lambda t: any(fw.startswith(s) for s in stems for fw in _norm(t).split())
            gone = [d["text"] for d in self._items if stems and hit(d["text"])]
            self._items = [d for d in self._items if d["text"] not in gone]
        if gone:
            self._save()
        return gone

    def prompt(self) -> str:
        if not self._items:
            return ""
        return "\n\nЧто ты знаешь о пользователе (он сам просил запомнить):\n" + "\n".join(f"- {t}" for t in self.facts())


store = Memory(config.DATA / "memory.json")
