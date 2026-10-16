#!/usr/bin/env python3
"""
shake-lens.py — «покрути мышкой по кругу» → скриншот в Google Lens.

Следит за курсором через сокет Hyprland (без прав на /dev/input).
Пока крутишь мышкой круги — по краям экрана растут чёрные рамки (прогресс шлём
в мини-шелл glow), набрал нужное число кругов — запускается выделение для Lens.

Настройки — ниже. Запускается из hyprland.conf: exec-once = ~/.config/hypr/scripts/shake-lens.py
"""
import json
import math
import os
import socket
import subprocess
import time

CIRCLES = 4.0        # на каком круге срабатывает
START = 2.0          # с какого круга начинают выезжать рамки (до этого — ничего не видно)
MEMORY = 10.0        # сек: как быстро «тает» накрученное во время движения (больше — легче докрутить)
STOP_FADE = 1.5      # сек: как быстро сбрасывается, если остановил мышь
NO_FULLSCREEN = True # не работать, когда открыто полноэкранное окно (игры, видео)
MIN_SPEED = 350.0    # px/с: медленнее — это не круги, а обычное движение
COOLDOWN = 1.5       # сек после срабатывания

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
HYPR = os.path.join(RUN, "hypr", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket.sock")
QS_SOCK = os.path.join(RUN, "qs-glow.sock")
LOCK = os.path.join(RUN, "shake-lens.lock")
SHOT = os.path.expanduser("~/.config/hypr/scripts/screenshot.sh")


def cursor():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(HYPR)
        s.sendall(b"j/cursorpos")
        data = b""
        while True:
            chunk = s.recv(256)
            if not chunk:
                break
            data += chunk
        p = json.loads(data)
        return float(p["x"]), float(p["y"])
    finally:
        s.close()


class Glow:
    """Отправка прогресса в мини-шелл glow (переподключается сам)."""
    def __init__(self):
        self.s = None
        self.last = -1.0

    def send(self, p, force=False):
        p = round(p, 3)
        if not force and abs(p - self.last) < 0.01:
            return
        for _ in range(2):
            try:
                if self.s is None:
                    self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    self.s.settimeout(0.1)
                    self.s.connect(QS_SOCK)
                self.s.sendall(f"p {p}\n".encode())
                self.last = p
                return
            except OSError:
                try:
                    self.s.close()
                except Exception:
                    pass
                self.s = None


def fullscreen():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(HYPR)
        s.sendall(b"j/activeworkspace")
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return bool(json.loads(data).get("hasfullscreen"))
    except Exception:
        return False
    finally:
        s.close()


def locked():
    try:
        return time.time() - os.path.getmtime(LOCK) < 60   # старше минуты — считаем мусором
    except OSError:
        return False


def main():
    glow = Glow()
    prev = None
    prev_v = None
    acc = 0.0                 # накрученный угол (рад), со знаком — направление вращения
    t_prev = time.monotonic()
    cooldown_until = 0.0
    target = CIRCLES * 2 * math.pi
    fs = False
    fs_check = 0.0

    while True:
        now = time.monotonic()
        dt = max(1e-3, now - t_prev)
        t_prev = now

        try:
            pos = cursor()
        except Exception:
            time.sleep(1.0)
            prev = prev_v = None
            continue

        # полноэкранное окно (игра) — проверяем раз в полсекунды и спим
        if NO_FULLSCREEN and now >= fs_check:
            fs = fullscreen()
            fs_check = now + 0.5
        if fs:
            acc = 0.0
            prev = prev_v = None
            glow.send(0.0)
            time.sleep(0.5)
            continue

        busy = locked() or now < cooldown_until
        moving = False
        if prev is not None and not busy:
            vx, vy = pos[0] - prev[0], pos[1] - prev[1]
            speed = math.hypot(vx, vy) / dt
            if speed > MIN_SPEED:
                moving = True
                if prev_v is not None:
                    px, py = prev_v
                    turn = math.atan2(px * vy - py * vx, px * vx + py * vy)
                    if abs(turn) < 1.3:          # резкие развороты — это тряска, не круг
                        acc += turn
                prev_v = (vx, vy)
            else:
                prev_v = None

        # «забывание»: остановился или сменил направление — прогресс тает
        acc *= math.exp(-dt / (MEMORY if moving else STOP_FADE))
        progress = 0.0 if busy else min(1.0, abs(acc) / target)
        circles = progress * CIRCLES
        # рамки: ноль до START-го круга, дальше плавно до полной к CIRCLES
        shown = min(1.0, max(0.0, (circles - START) / max(0.1, CIRCLES - START))) ** 0.8
        glow.send(shown)

        if progress >= 1.0:
            acc = 0.0
            prev_v = None
            cooldown_until = now + COOLDOWN
            glow.send(1.0, force=True); time.sleep(0.3)   # на миг полная рамка
            glow.send(0.0, force=True)
            open(LOCK, "w").close()
            subprocess.Popen([SHOT, "lens"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)

        prev = pos
        # быстро опрашиваем, только когда мышь двигается — в покое почти не тратим CPU
        time.sleep(1 / 90 if moving or progress > 0 else 1 / 12)


if __name__ == "__main__":
    main()
