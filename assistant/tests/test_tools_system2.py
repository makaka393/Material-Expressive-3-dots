"""Оболочка, справка, таймеры и напоминания, питание с подтверждением."""
import asyncio
import json
import tempfile
import time
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import tools
from glass_assistant.tools import base, info, power, shell, timers
from glass_assistant.tools.base import Result


class Calls(unittest.IsolatedAsyncioTestCase):
    """Записывает sh/qs/launch; ответы sh — из self.out по argv[0]."""

    def setUp(self):
        self.calls, self.out = [], {}

        async def sh(*argv, timeout=5):
            self.calls.append(("sh",) + argv)
            v = self.out.get(argv[0], "")
            return v(argv) if callable(v) else v

        async def qs(*a):
            self.calls.append(("qs",) + tuple(map(str, a)))
            return ""

        async def launch(*argv):
            self.calls.append(("launch",) + argv)
            return "ok"
        for p in (patch.object(base, "sh", sh), patch.object(base, "qs", qs), patch.object(base, "launch", launch)):
            p.start()
            self.addCleanup(p.stop)


class ShellTest(Calls):
    async def test_screenshot(self):
        await tools.run("screenshot", {"area": "region"})
        self.assertEqual(self.calls, [("launch", str(shell.SCRIPTS / "screenshot.sh"), "region")])

    async def test_record(self):
        await tools.run("screen_record", {"action": "start"})
        await tools.run("screen_record", {"action": "stop"})
        self.assertEqual(self.calls, [("launch", str(shell.SCRIPTS / "record.sh"), "start", "full", "1", "0", "0"),
                                      ("launch", str(shell.SCRIPTS / "record.sh"), "stop")])

    async def test_lock(self):
        r = await tools.run("lock_screen", {})
        self.assertEqual(self.calls, [("qs", "lock", "lock")])
        self.assertTrue(r.ok)

    async def test_wallpaper_random(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ("a.jpg", "b.mp4", "notes.txt"):
                (Path(d) / n).write_text("x")
            with patch.object(shell, "wallpaper_dir", lambda: Path(d)):
                r = await tools.run("wallpaper", {})
        (_, script, path), = self.calls
        self.assertEqual(script, str(shell.SCRIPTS / "changetheme.sh"))
        self.assertIn(Path(path).name, ("a.jpg", "b.mp4"))
        self.assertTrue(r.ok)

    async def test_wallpaper_empty_dir(self):
        with tempfile.TemporaryDirectory() as d, patch.object(shell, "wallpaper_dir", lambda: Path(d)):
            r = await tools.run("wallpaper", {})
        self.assertFalse(r.ok)

    async def test_radio(self):
        await tools.run("radio", {"device": "wifi", "on": False})
        await tools.run("radio", {"device": "bluetooth", "on": True})
        self.assertEqual(self.calls, [("sh", "nmcli", "radio", "wifi", "off"), ("sh", "bluetoothctl", "power", "on")])


class InfoTest(Calls):
    async def test_time_and_date(self):
        with patch.object(info, "now", lambda: datetime(2026, 10, 18, 14, 5)):
            t = await tools.run("system_info", {"kind": "time"})
            d = await tools.run("system_info", {"kind": "date"})
        self.assertEqual(t.say, "Сейчас 14:05.")
        self.assertEqual(d.say, "Сегодня воскресенье, 18 октября.")

    async def test_weather(self):
        data = {"current": {"temperature_2m": 12.4, "weather_code": 3, "wind_speed_10m": 9.0},
                "daily": {"temperature_2m_max": [14.2], "temperature_2m_min": [6.8]}}
        with patch.object(info, "fetch_json", AsyncMock(return_value=data)):
            r = await tools.run("system_info", {"kind": "weather"})
        self.assertEqual(r.say, "Сейчас 12°, пасмурно. Сегодня от 7 до 14°.")

    async def test_weather_offline(self):
        with patch.object(info, "fetch_json", AsyncMock(side_effect=OSError("сеть"))):
            r = await tools.run("system_info", {"kind": "weather"})
        self.assertFalse(r.ok)

    async def test_cpu(self):
        stats = iter(["cpu  100 0 100 800 0 0 0 0 0 0", "cpu  150 0 150 900 0 0 0 0 0 0"])
        with patch.object(info, "read", lambda p: next(stats) if p == "/proc/stat" else "48500"), \
                patch.object(info, "cpu_temp_path", lambda: "/sys/class/hwmon/hwmon1/temp1_input"), \
                patch.object(info, "SAMPLE", 0):
            r = await tools.run("system_info", {"kind": "cpu"})
        self.assertEqual(r.say, "Процессор загружен на 50%, 48°.")

    async def test_gpu(self):
        self.out["nvidia-smi"] = "23, 51, 5324, 8192"
        r = await tools.run("system_info", {"kind": "gpu"})
        self.assertEqual(r.say, "Видеокарта загружена на 23%, 51°, память 5,2 из 8 ГБ.")

    async def test_memory(self):
        with patch.object(info, "read", lambda p: "MemTotal: 65000000 kB\nMemFree: 1 kB\nMemAvailable: 56000000 kB\n"):
            r = await tools.run("system_info", {"kind": "memory"})
        self.assertEqual(r.say, "Занято 9 из 62 ГБ памяти.")

    async def test_now_playing(self):
        self.out["playerctl"] = "Metallica — One"
        r = await tools.run("system_info", {"kind": "now_playing"})
        self.assertEqual(r.say, "Играет Metallica — One.")

    async def test_headphones_from_upower(self):
        self.out["upower"] = lambda argv: ("/org/freedesktop/UPower/devices/headset_dev_AA\n" if argv[1] == "-e"
                                           else "  model: WH-1000XM4\n  percentage: 70%\n")
        r = await tools.run("system_info", {"kind": "headphones"})
        self.assertEqual(r.say, "WH-1000XM4: заряд 70%.")

    async def test_bluetoothctl_hangs(self):
        # bluetoothctl умеет зависать — это «наушников нет», а не ошибка
        self.out["upower"] = ""

        def hang(argv):
            raise RuntimeError("bluetoothctl не ответил")
        self.out["bluetoothctl"] = hang
        r = await tools.run("system_info", {"kind": "headphones"})
        self.assertEqual(r, Result(False, "Не вижу наушников с батареей", "Не вижу наушников с батареей."))

    async def test_no_headphones(self):
        self.out["upower"] = "/org/freedesktop/UPower/devices/DisplayDevice\n"
        r = await tools.run("system_info", {"kind": "headphones"})
        self.assertFalse(r.ok)


class TimersTest(Calls):
    def setUp(self):
        super().setUp()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "reminders.json"
        self.fired = []

        async def announce(text, kind):
            self.fired.append((kind, text))
        self.sched = timers.Scheduler(self.path, announce)
        p = patch.object(timers, "SCHED", self.sched)
        p.start()
        self.addCleanup(p.stop)

    async def test_timer_uses_shell(self):
        r = await tools.run("timer", {"hours": 1, "minutes": 30, "label": "пицца"})
        self.assertEqual(self.calls, [("qs", "timer", "start", "5400", "пицца")])
        self.assertEqual(r.say, "Таймер на 1 час 30 минут.")

    async def test_cancel_timer(self):
        await tools.run("cancel_timer", {})
        self.assertEqual(self.calls, [("qs", "timer", "stop")])

    async def test_reminder_in_minutes_saved(self):
        with patch.object(timers, "now", lambda: datetime(2026, 10, 18, 14, 0)):
            r = await tools.run("reminder", {"text": "выключить плиту", "in_minutes": 20})
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved[0]["text"], "выключить плиту")
        self.assertEqual(datetime.fromtimestamp(saved[0]["when"]), datetime(2026, 10, 18, 14, 20))
        self.assertEqual(r.say, "Напомню в 14:20.")

    async def test_reminder_at_time_tomorrow_if_past(self):
        with patch.object(timers, "now", lambda: datetime(2026, 10, 18, 20, 0)):
            await tools.run("reminder", {"text": "позвонить маме", "at": "18:00"})
        when = datetime.fromtimestamp(json.loads(self.path.read_text())[0]["when"])
        self.assertEqual(when, datetime(2026, 10, 19, 18, 0))

    async def test_alarm(self):
        with patch.object(timers, "now", lambda: datetime(2026, 10, 18, 23, 0)):
            r = await tools.run("alarm", {"time": "7:30"})
        saved = json.loads(self.path.read_text())[0]
        self.assertEqual((saved["kind"], datetime.fromtimestamp(saved["when"])), ("alarm", datetime(2026, 10, 19, 7, 30)))
        self.assertEqual(r.say, "Будильник на 07:30.")

    async def test_fires_and_survives_restart(self):
        self.sched.add(time.time() + 0.15, "проверка", "reminder")
        again = timers.Scheduler(self.path, self.sched.announce)      # служба перезапустилась
        task = asyncio.create_task(again.run(tick=0.02))
        await asyncio.sleep(0.4)
        task.cancel()
        self.assertEqual(self.fired, [("reminder", "проверка")])
        self.assertEqual(json.loads(self.path.read_text()), [])

    async def test_missed_while_off_fired_on_start(self):
        self.sched.add(time.time() - 600, "пропущенное", "reminder")
        task = asyncio.create_task(self.sched.run(tick=0.02))
        await asyncio.sleep(0.1)
        task.cancel()
        self.assertEqual(self.fired, [("reminder", "Пропущенное напоминание: пропущенное")])

    async def test_stale_dropped(self):
        self.sched.add(time.time() - 2 * 86400, "давно", "reminder")
        task = asyncio.create_task(self.sched.run(tick=0.02))
        await asyncio.sleep(0.1)
        task.cancel()
        self.assertEqual(self.fired, [])


class PowerTest(Calls):
    def setUp(self):
        super().setUp()
        power.PENDING = None

    async def test_asks_first_does_nothing(self):
        r = await tools.run("power", {"action": "shutdown"})
        self.assertEqual(self.calls, [])
        self.assertEqual(r.say, "Выключить компьютер? Скажи «да».")
        self.assertEqual(power.pending(), "shutdown")

    async def test_yes_executes(self):
        await tools.run("power", {"action": "reboot"})
        r = await power.confirm("Да, давай")
        self.assertEqual(self.calls, [("sh", "systemctl", "reboot")])
        self.assertEqual(r.say, "Перезагружаю.")
        self.assertIsNone(power.pending())

    async def test_no_cancels(self):
        await tools.run("power", {"action": "shutdown"})
        r = await power.confirm("нет, не надо")
        self.assertEqual(self.calls, [])
        self.assertEqual(r.say, "Отменил.")
        self.assertIsNone(power.pending())

    async def test_late_yes_ignored(self):
        await tools.run("power", {"action": "shutdown"})
        real = time.monotonic
        with patch.object(power.time, "monotonic", lambda: real() + 30):
            r = await power.confirm("да")
        self.assertIsNone(r)                      # вопрос протух: «да» — уже просто фраза
        self.assertEqual(self.calls, [])

    async def test_other_phrase_cancels_quietly(self):
        await tools.run("power", {"action": "suspend"})
        r = await power.confirm("какая погода")
        self.assertIsNone(r)
        self.assertIsNone(power.pending())
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
