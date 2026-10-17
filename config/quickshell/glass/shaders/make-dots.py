#!/usr/bin/env python3
"""Запекает текстуру светящихся точек для затемнения (Scrim.qml → shaders/scrim.frag).

Точки разбросаны «синим шумом» (диск Пуассона) — без сетки и без комков, тайл бесшовный
(расстояния считаются по тору). Каналы:
  R — сердцевина точки (чёткий кружок),
  G — свечение вокруг (гаусс, у каждой точки своя сила),
  B — фаза мерцания точки 0…1 (одна на всю точку и её свечение).
Шейдеру остаётся пара выборок из текстуры на пиксель вместо шума и хешей на каждый кадр.

  python3 make-dots.py [выход.png]     # по умолчанию dots.png рядом со скриптом
"""
import os
import sys

import numpy as np
from PIL import Image

T = 1024           # размер тайла, пиксели
R_MIN = 34         # минимальное расстояние между точками
SEED = 7


def poisson(rng, size, r, k=30):
    """Диск Пуассона (Бридсон) на торе."""
    cell = r / np.sqrt(2)
    n = int(np.ceil(size / cell))
    grid = -np.ones((n, n), dtype=int)
    pts, active = [], []

    def fits(p):
        gx, gy = int(p[0] / cell), int(p[1] / cell)
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                j = grid[(gx + dx) % n, (gy + dy) % n]
                if j >= 0:
                    d = np.abs(pts[j] - p)
                    d = np.minimum(d, size - d)
                    if d @ d < r * r:
                        return False
        return True

    def add(p):
        pts.append(p)
        active.append(len(pts) - 1)
        grid[int(p[0] / cell) % n, int(p[1] / cell) % n] = len(pts) - 1

    add(rng.uniform(0, size, 2))
    while active:
        i = active[rng.integers(len(active))]
        for _ in range(k):
            a = rng.uniform(0, 2 * np.pi)
            d = rng.uniform(r, 2 * r)
            p = (pts[i] + d * np.array([np.cos(a), np.sin(a)])) % size
            if fits(p):
                add(p)
                break
        else:
            active.remove(i)
    return np.array(pts)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "dots.png")
    rng = np.random.default_rng(SEED)
    pts = poisson(rng, T, R_MIN)

    core = np.zeros((T, T), np.float32)
    glow = np.zeros((T, T), np.float32)
    phase = np.zeros((T, T), np.float32)
    best = np.zeros((T, T), np.float32)          # чья точка здесь ярче — та и задаёт фазу

    for x, y in pts:
        u = rng.random()
        rc = 0.8 + 1.7 * u ** 2.4                # сердцевина: в основном мелкие, изредка крупные
        sigma = 2.2 + rc * 2.4                   # свечение шире у крупных
        amp = 0.35 + 0.65 * rng.random()
        ph = rng.random()
        reach = int(np.ceil(sigma * 3.2 + rc + 2))
        xs = np.arange(int(x) - reach, int(x) + reach + 1)
        ys = np.arange(int(y) - reach, int(y) + reach + 1)
        gx, gy = np.meshgrid(xs, ys)
        d = np.hypot(gx + 0.5 - x, gy + 0.5 - y)
        c = np.clip(rc + 0.5 - d, 0, 1)          # кружок со сглаженным краем
        g = amp * np.exp(-d * d / (2 * sigma * sigma))
        ix, iy = gx % T, gy % T
        core[iy, ix] = np.maximum(core[iy, ix], c)
        glow[iy, ix] += g
        mine = g > best[iy, ix]
        phase[iy[mine], ix[mine]] = ph
        best[iy[mine], ix[mine]] = g[mine]

    img = np.stack([core, np.clip(glow, 0, 1), phase], axis=-1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB").save(out, optimize=True)
    print(f"{out}: {len(pts)} точек, {os.path.getsize(out) // 1024} КБ")


if __name__ == "__main__":
    main()
