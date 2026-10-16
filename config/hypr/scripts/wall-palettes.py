#!/usr/bin/env python3
"""wall-palettes.py <картинка | #hex> <схема> <режим> [контраст]

Для пикера обоев: какие главные цвета matugen видит на обоях и какая из каждого
получится палитра. Печатает строки:  P <цвет-источник> <primary> <secondary> <tertiary> <primary_container>
Ничего не применяет (--dry-run).
Серые/белые/чёрные цвета считаются в монохроме (иначе matugen делает из белого голубой),
а для картинок в конце всегда есть свотч «mono» — чёрно-белая тема.
"""
import json
import re
import subprocess
import sys

# режим «палитра цветов»: wall-palettes.py --hexes "#e53935,#1e88e5,…" <схема> <режим> [контраст]
HEXES = None
if sys.argv[1] == "--hexes":
    HEXES = [h.strip() for h in sys.argv[2].split(",") if h.strip()]
    sys.argv = [sys.argv[0], "palette"] + sys.argv[3:]
img, scheme, mode = sys.argv[1:4]
contrast = sys.argv[4] if len(sys.argv) > 4 else "0"


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return ""


def low_chroma(c):
    r, g, b = (int(c[i:i + 2], 16) for i in (1, 3, 5))
    return max(r, g, b) - min(r, g, b) <= 24


def palette(args, sch=None):
    try:
        col = json.loads(run(args + ["-t", sch or scheme, "-m", mode, "--contrast", contrast, "--dry-run", "-j", "hex", "-q"]))["colors"]
        return [col[k]["default"]["color"] for k in ("primary", "secondary", "tertiary", "primary_container")]
    except Exception:
        return None


# готовая палитра цветов (не с обоев)
if HEXES is not None:
    for c in HEXES:
        c = "#" + c.lstrip("#").lower()
        p = palette(["matugen", "color", "hex", c], "scheme-monochrome" if low_chroma(c) else None)
        if p:
            print("\t".join(["P", c] + p), flush=True)
    p = palette(["matugen", "color", "hex", "#808080"], "scheme-monochrome")
    if p:
        print("\t".join(["P", "mono"] + p), flush=True)
    sys.exit(0)

# свой цвет из палитры: одна строка для него
if re.fullmatch(r"#?[0-9a-fA-F]{6}", img):
    c = "#" + img.lstrip("#").lower()
    p = palette(["matugen", "color", "hex", c], "scheme-monochrome" if low_chroma(c) else None)
    if p:
        print("\t".join(["P", c] + p), flush=True)
    sys.exit(0)

srcs = []
for c in re.findall(r"#[0-9a-fA-F]{6}", run(["matugen", "image", img, "--show-source-colors"])):
    if c.lower() not in srcs:
        srcs.append(c.lower())

# серые кандидаты (запасной синий matugen на серых обоях тоже) не показываем — для них есть «mono»
srcs = [c for c in srcs if not low_chroma(c)]
for c in srcs[:5]:
    p = palette(["matugen", "color", "hex", c])
    if p:
        print("\t".join(["P", c] + p), flush=True)

# чёрно-белая тема — для любых обоев
p = palette(["matugen", "color", "hex", "#808080"], "scheme-monochrome")
if p:
    print("\t".join(["P", "mono"] + p), flush=True)
