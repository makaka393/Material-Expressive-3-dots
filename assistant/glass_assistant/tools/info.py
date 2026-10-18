"""Справка: время, дата, погода, процессор, видеокарта, память, диск, наушники, что играет. Ответ — голосом."""
import asyncio
import re
import shutil
from datetime import datetime
from pathlib import Path

import httpx2

from . import base, register
from .base import Result, Tool

DAYS = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
WMO = {0: "ясно", 1: "в основном ясно", 2: "переменная облачность", 3: "пасмурно", 45: "туман", 48: "изморозь",
       51: "морось", 53: "морось", 55: "сильная морось", 56: "ледяная морось", 57: "ледяная морось",
       61: "небольшой дождь", 63: "дождь", 65: "сильный дождь", 66: "ледяной дождь", 67: "ледяной дождь",
       71: "небольшой снег", 73: "снег", 75: "сильный снег", 77: "снежная крупа", 80: "ливень", 81: "ливень",
       82: "сильный ливень", 85: "снегопад", 86: "сильный снегопад", 95: "гроза", 96: "гроза с градом", 99: "гроза с градом"}
SAMPLE = 0.25            # с между замерами /proc/stat


def now():
    return datetime.now()


def read(path):
    return Path(path).read_text()


async def fetch_json(url):
    async with httpx2.AsyncClient(timeout=6) as http:
        r = await http.get(url)
        r.raise_for_status()
        return r.json()


def cpu_temp_path():
    for h in Path("/sys/class/hwmon").glob("hwmon*"):
        try:
            if (h / "name").read_text().strip() in ("k10temp", "coretemp", "zenpower"):
                return str(h / "temp1_input")
        except OSError:
            continue
    return None


def latlon():
    """Координаты погоды оболочки (Theme.qml → lat, lon)."""
    try:
        t = (Path.home() / ".config/quickshell/glass/Theme.qml").read_text()
        lat = re.search(r"property real lat:\s*([-\d.]+)", t)
        lon = re.search(r"property real lon:\s*([-\d.]+)", t)
        if lat and lon:
            return float(lat.group(1)), float(lon.group(1))
    except OSError:
        pass
    return None


def gb(v):
    return f"{v:.1f}".rstrip("0").rstrip(".").replace(".", ",")


def _cpu_times(line):
    v = [int(x) for x in line.split()[1:]]
    return sum(v), v[3] + (v[4] if len(v) > 4 else 0)


async def _cpu():
    t1, i1 = _cpu_times(read("/proc/stat").splitlines()[0])
    await asyncio.sleep(SAMPLE)
    t2, i2 = _cpu_times(read("/proc/stat").splitlines()[0])
    load = round(100 * (1 - (i2 - i1) / max(1, t2 - t1)))
    p = cpu_temp_path()
    temp = f", {round(int(read(p).strip()) / 1000)}°" if p else ""
    return f"Процессор загружен на {load}%{temp}."


async def _gpu():
    out = await base.sh("nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                        "--format=csv,noheader,nounits")
    util, temp, used, total = [x.strip() for x in out.splitlines()[0].split(",")]
    return f"Видеокарта загружена на {util}%, {temp}°, память {gb(int(used) / 1024)} из {gb(int(total) / 1024)} ГБ."


def _memory():
    m = {k: int(v.split()[0]) for k, v in re.findall(r"^(\w+):\s+(.+)$", read("/proc/meminfo"), re.M)}
    total, avail = m["MemTotal"] / 1024 ** 2, m["MemAvailable"] / 1024 ** 2
    return f"Занято {round(total - avail)} из {round(total)} ГБ памяти."


async def _headphones():
    for dev in (await base.sh("upower", "-e")).split():
        if re.search(r"headset|headphones|audio|bluez", dev, re.I):
            d = await base.sh("upower", "-i", dev)
            pct = re.search(r"percentage:\s*([\d.]+%)", d)
            if pct:
                model = re.search(r"model:\s*(.+)", d)
                return f"{model.group(1).strip() if model else 'Наушники'}: заряд {pct.group(1)}."
    try:                                         # bluetoothctl умеет зависать — тогда «наушников нет»
        macs = re.findall(r"Device (\S+)", await base.sh("bluetoothctl", "devices", "Connected", timeout=1.5))
    except RuntimeError:
        return None
    for mac in macs:
        try:
            d = await base.sh("bluetoothctl", "info", mac, timeout=1.5)
        except RuntimeError:
            continue
        pct = re.search(r"Battery Percentage:.*\((\d+)\)", d)
        if pct:
            name = re.search(r"Name:\s*(.+)", d)
            return f"{name.group(1).strip() if name else 'Наушники'}: заряд {pct.group(1)}%."
    return None


async def system_info(args):
    kind = args["kind"]
    if kind == "time":
        text = f"Сейчас {now():%H:%M}."
    elif kind == "date":
        d = now()
        text = f"Сегодня {DAYS[d.weekday()]}, {d.day} {MONTHS[d.month - 1]}."
    elif kind == "weather":
        ll = latlon() or (42.6977, 23.3219)
        try:
            w = await fetch_json(f"https://api.open-meteo.com/v1/forecast?latitude={ll[0]}&longitude={ll[1]}"
                                 "&current=temperature_2m,weather_code,wind_speed_10m"
                                 "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto")
        except Exception:
            return Result(False, "Не получилось узнать погоду", "Не получилось узнать погоду.")
        c, day = w["current"], w["daily"]
        text = (f"Сейчас {round(c['temperature_2m'])}°, {WMO.get(c['weather_code'], 'без осадков')}. "
                f"Сегодня от {round(day['temperature_2m_min'][0])} до {round(day['temperature_2m_max'][0])}°.")
    elif kind == "cpu":
        text = await _cpu()
    elif kind == "gpu":
        text = await _gpu()
    elif kind == "memory":
        text = _memory()
    elif kind == "disk":
        u = shutil.disk_usage("/")
        text = f"Свободно {round(u.free / 1024 ** 3)} из {round(u.total / 1024 ** 3)} ГБ на диске."
    elif kind == "headphones":
        text = await _headphones()
        if not text:
            return Result(False, "Не вижу наушников с батареей", "Не вижу наушников с батареей.")
    elif kind == "now_playing":
        try:
            song = (await base.sh("playerctl", "metadata", "--format", "{{artist}} — {{title}}")).strip(" —\n")
        except RuntimeError:
            song = ""
        text = f"Играет {song}." if song else "Сейчас ничего не играет."
    else:
        return Result(False, f"Не знаю, как узнать «{kind}»")
    return Result(True, text, text)


register(Tool("system_info", "Справка — ответить голосом: время, дата, погода (в городе пользователя — не переспрашивай), "
              "загрузка процессора, видеокарты, память, "
              "место на диске, заряд наушников, что сейчас играет",
              {"kind": {"type": "string", "enum": ["time", "date", "weather", "cpu", "gpu", "memory", "disk",
                                                   "headphones", "now_playing"]}}, ["kind"], system_info))
