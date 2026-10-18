"""Числа — словами для озвучки: Silero цифры не читает («Будет 391» звучит как «Будет»).

Без склонений по падежам: «в 14:05» → «в четырнадцать ноль пять», «30%» → «тридцать процентов».
"""
import re

UNITS = ["ноль", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
         "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать",
         "семнадцать", "восемнадцать", "девятнадцать"]
FEM = {1: "одна", 2: "две"}
TENS = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто"]
HUNDREDS = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот"]
SCALES = [(10 ** 9, ("миллиард", "миллиарда", "миллиардов"), False),
          (10 ** 6, ("миллион", "миллиона", "миллионов"), False),
          (10 ** 3, ("тысяча", "тысячи", "тысяч"), True)]
PERCENT = ("процент", "процента", "процентов")


def plural(n: int, forms) -> str:
    n = abs(n) % 100
    if 11 <= n <= 19:
        return forms[2]
    n %= 10
    return forms[0] if n == 1 else forms[1] if 2 <= n <= 4 else forms[2]


def _triple(n: int, fem: bool) -> list:
    out = []
    h, r = divmod(n, 100)
    if h:
        out.append(HUNDREDS[h])
    if r >= 20:
        t, r = divmod(r, 10)
        out.append(TENS[t])
    if r:
        out.append(FEM[r] if fem and r in FEM else UNITS[r])
    return out


def words(n: int) -> str:
    if n == 0:
        return "ноль"
    out = ["минус"] if n < 0 else []
    n = abs(n)
    for scale, forms, fem in SCALES:
        q, n = divmod(n, scale)
        if q:
            out += _triple(q, fem) + [plural(q, forms)]
    return " ".join(out + _triple(n, False))


def _number(s: str) -> str:
    """«-3,05» → «минус три запятая ноль пять»."""
    sign = "минус " if s.startswith("-") else ""
    whole, _, frac = s.lstrip("-").replace(",", ".").partition(".")
    out = words(int(whole))
    if frac:
        zeros = len(frac) - len(frac.lstrip("0"))
        out += " запятая " + " ".join(["ноль"] * zeros + ([words(int(frac))] if frac.strip("0") else []))
    return sign + out


def _time(m) -> str:
    h, mm = int(m.group(1)), int(m.group(2))
    return f"{words(h)} " + ("ноль ноль" if mm == 0 else f"ноль {words(mm)}" if mm < 10 else words(mm))


def _percent(m) -> str:
    s = m.group(1)
    form = PERCENT[1] if re.search(r"[.,]", s) else plural(int(s.lstrip("-")), PERCENT)
    return f"{_number(s)} {form}"


NUM = r"(?<![\w-])-?\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?"


def spoken(text: str) -> str:
    if not re.search(r"\d", text):
        return text
    text = re.sub(r"\b(\d{1,2}):(\d{2})\b", _time, text)
    text = re.sub(rf"({NUM})\s*%", _percent, text)
    return re.sub(NUM, lambda m: _number(m.group()), text)
