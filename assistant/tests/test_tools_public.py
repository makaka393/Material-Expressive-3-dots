"""Инструменты, которые видит модель: укрупнённые (16 вместо 27) — маленькая модель путалась в длинном списке
(eval 60/78). Под ними — те же обработчики."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import memory, tools
from glass_assistant.tools import base, shell, timers

PUBLIC = {"media", "play_music", "volume", "brightness", "toggle", "app", "web", "window", "workspace", "browser_tab",
          "screen", "system_info", "timer", "reminder", "power", "memory"}


class PublicTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.calls = []

        async def sh(*argv, timeout=5):
            self.calls.append(("sh",) + argv)
            if argv[:3] == ("hyprctl", "clients", "-j"):
                return "[]"
            if argv[:3] == ("hyprctl", "activewindow", "-j"):
                return json.dumps({"address": "0x9", "class": "kitty"})
            return ""

        async def qs(*a):
            self.calls.append(("qs",) + tuple(map(str, a)))
            return ""

        async def launch(*argv):
            self.calls.append(("launch",) + argv)
            return "ok"
        for p in (patch.object(base, "sh", sh), patch.object(base, "qs", qs), patch.object(base, "launch", launch)):
            p.start()
            self.addCleanup(p.stop)

    def test_visible_set(self):
        self.assertEqual({t["function"]["name"] for t in tools.openai_tools()}, PUBLIC)
        self.assertEqual({t["name"] for t in tools.anthropic_tools()}, PUBLIC)

    async def test_hidden_still_runnable(self):
        await tools.run("night_light", {"on": True})
        self.assertEqual(self.calls, [("qs", "night", "enable")])

    async def test_toggle(self):
        await tools.run("toggle", {"feature": "night_light", "on": False})
        await tools.run("toggle", {"feature": "do_not_disturb", "on": True})
        await tools.run("toggle", {"feature": "wifi", "on": False})
        self.assertEqual(self.calls, [("qs", "night", "disable"), ("qs", "notifs", "set", "true"),
                                      ("sh", "nmcli", "radio", "wifi", "off")])

    async def test_app(self):
        with patch("glass_assistant.tools.apps.find", lambda n: None):
            r = await tools.run("app", {"action": "open", "name": "гитхаб"})
        self.assertEqual(self.calls[-1], ("launch", "xdg-open", "https://github.com"))
        self.assertTrue(r.ok)

    async def test_web(self):
        await tools.run("web", {"url": "github.com"})
        await tools.run("web", {"query": "курс доллара"})
        self.assertEqual(self.calls, [("launch", "xdg-open", "https://github.com"),
                                      ("launch", "xdg-open", "https://www.google.com/search?q=%D0%BA%D1%83%D1%80%D1%81+"
                                                             "%D0%B4%D0%BE%D0%BB%D0%BB%D0%B0%D1%80%D0%B0")])

    async def test_window_move_and_close(self):
        await tools.run("window", {"action": "move", "workspace": 5})
        await tools.run("window", {"action": "close"})
        self.assertEqual([c[3] for c in self.calls if c[1:3] == ("hyprctl", "dispatch")],
                         ["hl.dsp.window.move({ workspace = 5 })", "hl.dsp.window.close()"])

    async def test_screen(self):
        await tools.run("screen", {"action": "lock"})
        await tools.run("screen", {"action": "screenshot_region"})
        await tools.run("screen", {"action": "record"})
        self.assertEqual(self.calls, [("qs", "lock", "lock"), ("launch", str(shell.SCRIPTS / "screenshot.sh"), "region"),
                                      ("launch", str(shell.SCRIPTS / "record.sh"), "start", "full", "1", "0", "0")])

    async def test_timer(self):
        await tools.run("timer", {"action": "start", "minutes": 10})
        await tools.run("timer", {"action": "stop"})
        self.assertEqual(self.calls, [("qs", "timer", "start", "600", ""), ("qs", "timer", "stop")])

    async def test_reminder_and_alarm(self):
        with tempfile.TemporaryDirectory() as d:
            sched = timers.Scheduler(Path(d) / "r.json", AsyncMock())
            with patch.object(timers, "SCHED", sched):
                await tools.run("reminder", {"text": "плита", "in_minutes": 20})
                await tools.run("reminder", {"at": "7:30", "alarm": True})
            self.assertEqual([i["kind"] for i in sched.items], ["reminder", "alarm"])

    async def test_memory(self):
        with tempfile.TemporaryDirectory() as d, patch.object(memory, "store", memory.Memory(Path(d) / "m.json")):
            await tools.run("memory", {"action": "remember", "text": "Любит Metallica"})
            self.assertEqual(memory.store.facts(), ["Любит Metallica"])
            await tools.run("memory", {"action": "forget", "text": "metallica"})
            self.assertEqual(memory.store.facts(), [])


if __name__ == "__main__":
    unittest.main()
