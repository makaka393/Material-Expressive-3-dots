import asyncio
import time
import unittest
from unittest.mock import patch

from glass_assistant import tools
from glass_assistant.tools.base import Result, Tool

seen = []


async def echo(args):
    seen.append(args)
    return Result(True, "ок")


async def boom(args):
    raise RuntimeError("нет плеера")


async def sleepy(args):
    await asyncio.sleep(6)
    return Result(True, "проснулся")


TEST_TOOLS = {
    "echo": Tool("echo", "Повторить", {"level": {"type": "integer"}, "on": {"type": "boolean"}}, ["level"], echo),
    "boom": Tool("boom", "Сломаться", {}, [], boom),
    "sleepy": Tool("sleepy", "Уснуть", {}, [], sleepy),
    "hint": Tool("hint", "Подсказка", {}, [], None),
}


class RunTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        seen.clear()
        p = patch.dict(tools.TOOLS, TEST_TOOLS, clear=True)
        p.start()
        self.addCleanup(p.stop)

    async def test_unknown_tool(self):
        r = await tools.run("nope", {})
        self.assertFalse(r.ok)
        self.assertIn("nope", r.show)

    async def test_coerces_numbers_and_bools(self):
        r = await tools.run("echo", {"level": "40", "on": "true"})
        self.assertTrue(r.ok)
        self.assertEqual(seen, [{"level": 40, "on": True}])

    async def test_negative_number_string(self):
        await tools.run("echo", {"level": "-20"})
        self.assertEqual(seen, [{"level": -20}])

    async def test_json_string_args(self):
        await tools.run("echo", '{"level": 7}')
        self.assertEqual(seen, [{"level": 7}])

    async def test_bad_json_args(self):
        r = await tools.run("echo", "{level: 4")
        self.assertFalse(r.ok)
        self.assertEqual(seen, [])

    async def test_bad_number(self):
        r = await tools.run("echo", {"level": "громко"})
        self.assertFalse(r.ok)
        self.assertEqual(seen, [])

    async def test_unexpected_arg_dropped(self):
        await tools.run("echo", {"level": 1, "zzz": 2})
        self.assertEqual(seen, [{"level": 1}])

    async def test_handler_exception(self):
        r = await tools.run("boom", {})
        self.assertEqual(r, Result(False, "Не получилось: нет плеера"))

    async def test_handler_timeout(self):
        with patch.object(tools, "TIMEOUT", 0.2):
            t = time.monotonic()
            r = await tools.run("sleepy", {})
        self.assertFalse(r.ok)
        self.assertLess(time.monotonic() - t, 1)

    async def test_no_handler(self):
        self.assertEqual(await tools.run("hint", {}), Result(True, ""))


class SchemaTest(unittest.TestCase):
    def setUp(self):
        p = patch.dict(tools.TOOLS, TEST_TOOLS, clear=True)
        p.start()
        self.addCleanup(p.stop)

    def test_openai(self):
        echo_tool = next(t for t in tools.openai_tools() if t["function"]["name"] == "echo")
        self.assertEqual(echo_tool, {"type": "function", "function": {
            "name": "echo", "description": "Повторить",
            "parameters": {"type": "object", "properties": TEST_TOOLS["echo"].params, "required": ["level"]}}})
        self.assertEqual(len(tools.openai_tools()), 4)

    def test_anthropic(self):
        a = tools.anthropic_tools()
        self.assertEqual([t["name"] for t in a], ["echo", "boom", "sleepy", "hint"])
        self.assertEqual(a[0], {"name": "echo", "description": "Повторить", "input_schema": {
            "type": "object", "properties": TEST_TOOLS["echo"].params, "required": ["level"]}})


if __name__ == "__main__":
    unittest.main()


class SessionEnvTest(unittest.TestCase):
    """Служба стартует раньше, чем Hyprland передаёт systemd свои переменные, — сокет ищем сами."""

    def test_finds_hyprland_and_wayland_sockets(self):
        import os
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        from glass_assistant.tools import base
        run = Path(tempfile.mkdtemp())
        (run / "hypr" / "abc_123").mkdir(parents=True)
        (run / "hypr" / "abc_123" / ".socket.sock").touch()
        (run / "hypr" / "old_1").mkdir()                       # мёртвый — без сокета
        (run / "wayland-1").touch()
        (run / "wayland-1.lock").touch()
        clean = {k: v for k, v in os.environ.items() if k not in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY")}
        with patch.dict(os.environ, {**clean, "XDG_RUNTIME_DIR": str(run)}, clear=True):
            env = base.session_env()
            self.assertEqual((env["HYPRLAND_INSTANCE_SIGNATURE"], env["WAYLAND_DISPLAY"]), ("abc_123", "wayland-1"))
        with patch.dict(os.environ, {**clean, "XDG_RUNTIME_DIR": str(run), "HYPRLAND_INSTANCE_SIGNATURE": "old_1"}, clear=True):
            self.assertEqual(base.session_env()["HYPRLAND_INSTANCE_SIGNATURE"], "abc_123")


class InstalledTest(unittest.TestCase):
    def test_list_and_query(self):
        from unittest.mock import patch
        from glass_assistant.tools import apps, info
        fake = [apps.Entry("steam", "Steam", "steam", "steam", "steam"), apps.Entry("org.telegram.desktop", "Telegram", "", "telegram-desktop", "telegram")]
        with patch.object(apps, "entries", return_value=fake), patch("shutil.which", return_value=None):
            r = info.installed("")
            self.assertIn("Steam", r.data)
            self.assertIn("2 приложений", r.say)
            self.assertIn("Telegram установлен", info.installed("телегу").show)
            self.assertIn("не установлен", info.installed("фотошоп").show)

    def test_intent(self):
        from glass_assistant import intents
        self.assertEqual(intents.match("что у меня установлено"), ("system_info", {"kind": "apps"}))

    def test_far_mic(self):
        from glass_assistant import config
        self.assertEqual(config.mic(config.DEFAULTS, aod=True), "glass_vega_mic")
        self.assertEqual(config.mic({**config.DEFAULTS, "near_mic": False}), "glass_vega_mic")
        self.assertEqual(config.mic({**config.DEFAULTS, "far_mic": False, "mic": "x"}), "x")
        self.assertEqual(config.mic({**config.DEFAULTS, "far_mic": False, "mic": "x"}, aod=True), "x")

    def test_near_mic_by_default(self):
        # за столом — ближний источник без автоусиления и высокий порог: дальние голоса не слышит;
        # в AOD (от компьютера отошли) — дальний, как раньше
        from glass_assistant import config
        self.assertEqual(config.mic(config.DEFAULTS), "glass_vega_near")
        self.assertEqual(config.speech_min(config.DEFAULTS), config.NEAR_MIN)
        self.assertEqual(config.speech_min(config.DEFAULTS, aod=True), 450.0)
        self.assertEqual(config.speech_min({**config.DEFAULTS, "far_mic": False}), 450.0)

