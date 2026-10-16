#!/usr/bin/env python3
"""exact-accent.py <#hex>

Режим «Точный цвет»: Material в тёмной теме всегда делает основной цвет пастельным
(красный → светло-коралловый). Этот скрипт после matugen подменяет primary во всех
сгенерированных файлах (бар, Hyprland, kitty, GTK, rofi, btop, KDE, SDDM) на ровно
выбранный цвет, а текст поверх него — на чёрный или белый, что читается лучше.
Второй цвет (secondary/tertiary — например, второй цвет градиента рамок окон) — тот же
оттенок, но мягче: менее насыщенный и светлее, чтобы подходил к основному.
"""
import colorsys
import json
import os
import re
import sys
import tomllib

H = os.path.expanduser


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(h):
    def ch(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


want = "#" + sys.argv[1].lstrip("#").lower()
if not re.fullmatch(r"#[0-9a-f]{6}", want):
    sys.exit(0)

def hsl(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h % 1, max(0, min(1, l)), max(0, min(1, s)))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def on(c):
    return "#ffffff" if contrast(c, "#ffffff") >= contrast(c, "#101010") else "#101010"


try:
    cur = json.load(open(H("~/.cache/matugen/colors.json")))
except Exception:
    sys.exit(0)

dark = lum(cur.get("surface", "#111318")) < 0.2
r, g, b = (v / 255 for v in rgb(want))
h, l, s = colorsys.rgb_to_hls(r, g, b)
# второй цвет — тот же оттенок, мягче (меньше насыщенность, другая светлота)
soft = max(0.25, s * 0.55)
tert = hsl(h + 0.025, max(0.35, s * 0.85), 0.65 if dark else 0.40)     # чуть сдвинутый тон — для градиентов
sec = hsl(h, soft, 0.76 if dark else 0.36)
cont_l, cont_fg_l = (0.24, 0.88) if dark else (0.88, 0.18)

new = {
    "primary": want,
    "primaryFg": on(want),
    "tertiary": tert,
    "tertiaryContainer": hsl(h + 0.025, soft, cont_l),
    "tertiaryContainerFg": hsl(h + 0.025, soft, cont_fg_l),
    "secondary": sec,
    "secondaryContainer": hsl(h, soft * 0.8, cont_l),
    "secondaryContainerFg": hsl(h, soft, cont_fg_l),
}
pairs = []
seen = set()
for k, v in new.items():
    old = (cur.get(k) or "").lower()
    if re.fullmatch(r"#[0-9a-f]{6}", old) and old not in seen and old != v:
        pairs.append((old, v))
        seen.add(old)

try:
    cfg = tomllib.load(open(H("~/.config/matugen/config.toml"), "rb"))
    outs = [H(t["output_path"]) for t in cfg.get("templates", {}).values() if "output_path" in t]
except Exception:
    outs = []
outs.append(H("~/.cache/matugen/colors.json"))

# замена за один проход (чтобы новый цвет случайно не заменился ещё раз)
hexmap = {o.lstrip("#"): n.lstrip("#") for o, n in pairs}
trimap = {",".join(map(str, rgb(o))): ",".join(map(str, rgb(n))) for o, n in pairs}
if not hexmap:
    sys.exit(0)
hex_re = re.compile("|".join(map(re.escape, hexmap)), re.I)                       # hex с # и без
tri_re = re.compile(r"(?<![\d.])(" + "|".join(map(re.escape, trimap)) + r")(?![\d.])")  # KDE: «r,g,b»

for path in dict.fromkeys(outs):
    try:
        s = open(path).read()
    except Exception:
        continue
    t = hex_re.sub(lambda m: hexmap[m.group(0).lower()], s)
    t = tri_re.sub(lambda m: trimap[m.group(1)], t)
    if t != s:
        open(path, "w").write(t)
