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
    "hint": Tool("hint", "Подсказка", {}, [], None, claude=False),
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
        self.assertEqual([t["name"] for t in a], ["echo", "boom", "sleepy"])   # без claude=False
        self.assertEqual(a[0], {"name": "echo", "description": "Повторить", "input_schema": {
            "type": "object", "properties": TEST_TOOLS["echo"].params, "required": ["level"]}})


if __name__ == "__main__":
    unittest.main()
