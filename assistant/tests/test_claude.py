import os
import unittest
from types import SimpleNamespace as NS
from unittest.mock import patch

from glass_assistant import claude, config, tools
from glass_assistant.claude import ClaudeBrain, MissingKey
from glass_assistant.tools.base import Result, Tool


def text_block(s):
    return NS(type="text", text=s)


def tool_block(id, name, input):
    return NS(type="tool_use", id=id, name=name, input=input)


class FakeStream:
    def __init__(self, chunks, final):
        self.chunks, self.final = chunks, final

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    @property
    async def text_stream(self):
        for c in self.chunks:
            yield c

    async def get_final_message(self):
        return self.final


class FakeClient:
    """Отвечает по сценарию: [(куски текста, блоки, stop_reason), …]; запоминает запросы."""

    def __init__(self, rounds):
        self.rounds, self.calls = list(rounds), []
        self.beta = NS(messages=NS(stream=self.stream))

    def stream(self, **kw):
        self.calls.append({**kw, "messages": list(kw["messages"])})
        chunks, blocks, stop = self.rounds.pop(0) if self.rounds else (["ещё"], [tool_block("x", "volume", {"change": 1})], "tool_use")
        return FakeStream(chunks, NS(content=blocks, stop_reason=stop))


ran = []


async def volume(args):
    ran.append(args)
    return Result(True, "Громкость 50%")


class ClaudeTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        ran.clear()
        for p in (patch.dict(tools.TOOLS, {"volume": Tool("volume", "Громкость", {"change": {"type": "integer"}}, [], volume)}),
                  patch("glass_assistant.config.load", return_value=dict(config.DEFAULTS)),
                  patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test"})):
            p.start()
            self.addCleanup(p.stop)
        self.brain = ClaudeBrain()
        self.deltas, self.actions = [], []

    def use(self, rounds):
        self.client = FakeClient(rounds)
        self.brain._claude = lambda: self.client

    async def ask(self, q, voice=False):
        async def on_delta(s):
            self.deltas.append(s)

        async def on_action(a):
            self.actions.append(a)
        return await self.brain.answer(q, voice, on_delta, on_action)

    async def test_text_answer(self):
        self.use([(["При", "вет"], [text_block("Привет")], "end_turn")])
        reply = await self.ask("привет")
        self.assertEqual(reply.text, "Привет")
        self.assertEqual(self.deltas, ["При", "вет"])

    async def test_tool_round(self):
        first = [text_block("Сейчас."), tool_block("t1", "volume", {"change": 10})]
        self.use([(["Сейчас."], first, "tool_use"), (["Готово."], [text_block("Готово.")], "end_turn")])
        reply = await self.ask("сделай громче")
        self.assertEqual(ran, [{"change": 10}])
        second = self.client.calls[1]["messages"]
        self.assertEqual(second[-2], {"role": "assistant", "content": first})
        self.assertEqual(second[-1], {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "Громкость 50%"}]})
        self.assertEqual(self.actions[0]["show"], "Громкость 50%")
        self.assertEqual(reply.actions, self.actions)
        self.assertEqual(reply.text, "Сейчас. Готово.")

    async def test_tool_error_marked(self):
        async def broken(args):
            return Result(False, "Не получилось: сломано")
        tools.TOOLS["volume"] = Tool("volume", "Громкость", {}, [], broken)
        self.use([([], [tool_block("t1", "volume", {})], "tool_use"), (["Увы."], [text_block("Увы.")], "end_turn")])
        await self.ask("громче")
        result = self.client.calls[1]["messages"][-1]["content"][0]
        self.assertTrue(result["is_error"])

    async def test_tool_rounds_capped(self):
        self.use([])                                   # всё время просит инструмент
        reply = await self.ask("громче")
        self.assertEqual(len(self.client.calls), 5)
        self.assertTrue(reply.text.endswith("Не получилось закончить."))

    async def test_missing_key(self):
        self.use([])
        with patch.dict(os.environ, {}, clear=True), patch("glass_assistant.config.has_key", return_value=False):
            with self.assertRaises(MissingKey):
                await self.ask("привет")

    async def test_tools_passed(self):
        self.use([(["а"], [text_block("а")], "end_turn")])
        await self.ask("привет")
        self.assertEqual(self.client.calls[0]["tools"], tools.anthropic_tools())

    async def test_memory_in_system(self):
        import tempfile
        from pathlib import Path
        from glass_assistant import memory
        m = memory.Memory(Path(tempfile.mkdtemp()) / "m.json")
        m.add("Пользователя зовут Рома")
        self.use([(["а"], [text_block("а")], "end_turn")])
        with patch.object(memory, "store", m):
            await self.ask("как меня зовут")
        self.assertIn("- Пользователя зовут Рома", self.client.calls[0]["system"])

    async def test_name_in_system(self):
        self.use([(["а"], [text_block("а")], "end_turn")])
        await self.ask("кто ты")
        self.assertIn("Ты — Аянами", self.client.calls[0]["system"])

    async def test_history_append_only(self):
        # история только дописывается: следующий запрос начинается ровно с предыдущего
        self.use([(["а"], [text_block("а")], "end_turn"), (["б"], [text_block("б")], "end_turn")])
        await self.ask("раз", voice=True)
        await self.ask("два")
        first, second = self.client.calls[0]["messages"], self.client.calls[1]["messages"]
        self.assertEqual(second[:len(first)], first)
        self.assertEqual(first[-1], {"role": "system", "content": claude.VOICE_NOTE})

    async def test_failed_request_rolls_back(self):
        class Boom(FakeClient):
            def stream(self, **kw):
                raise claude.anthropic.APIConnectionError(request=NS())
        self.client = Boom([])
        self.brain._claude = lambda: self.client
        with self.assertRaises(claude.anthropic.APIConnectionError):
            await self.ask("привет")
        self.assertEqual(self.brain.conv.messages, [])


if __name__ == "__main__":
    unittest.main()
