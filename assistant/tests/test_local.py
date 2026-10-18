import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import config, tools
from glass_assistant.local import LocalBrain, LocalServer, Reply
from glass_assistant.tools.base import Result, Tool


def text(s):
    return {"content": s}


def call(i, name=None, args="", id=None):
    f = {"arguments": args}
    if name:
        f["name"] = name
    return {"tool_calls": [{"index": i, "id": id, "type": "function", "function": f}]}


class FakeLlama:
    """llama-server понарошку: /health и потоковые ответы по сценарию (список кусков на запрос)."""

    def __init__(self):
        self.replies, self.bodies = [], []

    async def start(self):
        self.server = await asyncio.start_server(self.handle, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.url = f"http://127.0.0.1:{self.port}"

    async def close(self):
        self.server.close()
        await self.server.wait_closed()

    async def handle(self, reader, writer):
        head = (await reader.readuntil(b"\r\n\r\n")).decode().split("\r\n")
        path = head[0].split(" ")[1]
        length = next((int(h.split(":")[1]) for h in head if h.lower().startswith("content-length")), 0)
        body = await reader.readexactly(length) if length else b""
        if path == "/health":
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        else:
            self.bodies.append(json.loads(body))
            chunks = self.replies.pop(0)
            data = "".join(f"data: {json.dumps({'choices': [{'delta': d}]})}\n\n" for d in chunks) + "data: [DONE]\n\n"
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n" + data.encode())
        await writer.drain()
        writer.close()


class FakeServer:
    def __init__(self, url):
        self.url = url
        self.ensure = AsyncMock()


ran = []


def recorder(result):
    async def handler(args):
        ran.append(args)
        return result
    return handler


TEST_TOOLS = {
    "volume": Tool("volume", "Громкость", {"change": {"type": "integer"}}, [], recorder(Result(True, "Громкость 50%"))),
    "lock_screen": Tool("lock_screen", "Заблокировать", {}, [], recorder(Result(True, "Экран заблокирован"))),
    "broken": Tool("broken", "Сломаться", {}, [], recorder(Result(False, "Не получилось: сломано"))),
}


class BrainTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        ran.clear()
        self.llama = FakeLlama()
        await self.llama.start()
        self.addAsyncCleanup(self.llama.close)
        for p in (patch.dict(tools.TOOLS, TEST_TOOLS), patch("glass_assistant.config.load", return_value=dict(config.DEFAULTS))):
            p.start()
            self.addCleanup(p.stop)
        self.brain = LocalBrain(FakeServer(self.llama.url))
        self.deltas, self.actions = [], []

    async def ask(self, q, voice=False):
        async def on_delta(s):
            self.deltas.append(s)

        async def on_action(a):
            self.actions.append(a)
        return await self.brain.answer(q, voice, on_delta, on_action)

    async def test_streams_text_and_strips_stamp(self):
        self.llama.replies = [[text("[2026-10-18 14:05, "), text("воскресенье] "), text("Привет"), text("!")]]
        reply = await self.ask("привет")
        self.assertEqual("".join(self.deltas), "Привет!")
        self.assertEqual(reply, Reply("Привет!", [], False))

    async def test_tool_call_from_chunks(self):
        self.llama.replies = [[call(0, "volume", '{"cha', id="c1"), call(0, args='nge": 10}')]]
        reply = await self.ask("сделай громче")
        self.assertEqual(ran, [{"change": 10}])
        self.assertEqual(len(self.llama.bodies), 1)                      # второго прохода модели нет
        self.assertEqual(self.actions, [{"name": "volume", "args": {"change": 10}, "ok": True, "show": "Громкость 50%", "say": None}])
        self.assertEqual(reply.actions, self.actions)
        self.assertEqual(reply.text, "")

    async def test_claim_without_call_retries(self):
        self.llama.replies = [[text("Блокирую "), text("экран.")], [call(0, "lock_screen", "{}", id="c1")]]
        reply = await self.ask("я ухожу, заблокируй")
        self.assertEqual(self.llama.bodies[1].get("tool_choice"), "required")
        self.assertEqual(ran, [{}])
        self.assertEqual(self.deltas, [])
        self.assertEqual(reply.text, "")

    async def test_two_actions_one_fails(self):
        self.llama.replies = [[call(0, "broken", "{}", id="a"), call(1, "volume", '{"change": 10}', id="b")]]
        reply = await self.ask("сломайся и громче")
        self.assertEqual([a["name"] for a in reply.actions], ["broken", "volume"])
        self.assertEqual([a["ok"] for a in reply.actions], [False, True])

    async def test_suggest(self):
        self.llama.replies = [[call(0, tools.SUGGEST, "{}", id="s")]]
        reply = await self.ask("докажи гипотезу римана")
        self.assertTrue(reply.suggest)
        self.assertEqual(reply.text, "Это лучше спросить у Claude — скажи «морковь».")
        self.assertEqual("".join(self.deltas), reply.text)

    async def test_history_kept_and_trimmed(self):
        for i in range(7):
            self.llama.replies.append([text(f"ответ {i}")])
            await self.ask(f"вопрос {i}")
        self.llama.replies.append([text("ещё")])
        await self.ask("вопрос 7")
        users = [m["content"] for m in self.llama.bodies[-1]["messages"] if m["role"] == "user"]
        self.assertEqual(len(users), 7)                                  # 6 прошлых + текущий
        self.assertIn("вопрос 1", users[0])
        with patch("glass_assistant.local.time.monotonic", return_value=10 ** 9):
            self.llama.replies.append([text("пусто")])
            await self.ask("вопрос 8")
        users = [m for m in self.llama.bodies[-1]["messages"] if m["role"] == "user"]
        self.assertEqual(len(users), 1)

    async def test_history_keeps_tool_calls(self):
        self.llama.replies = [[call(0, "volume", '{"change": 10}', id="c1")], [text("ок")]]
        await self.ask("громче")
        await self.ask("а теперь ещё")
        msgs = self.llama.bodies[1]["messages"]
        self.assertEqual([m["role"] for m in msgs], ["system", "user", "assistant", "tool", "user"])
        self.assertEqual(msgs[2]["tool_calls"][0]["function"], {"name": "volume", "arguments": '{"change": 10}'})
        self.assertEqual(msgs[3], {"role": "tool", "tool_call_id": "c1", "content": "Громкость 50%"})

    async def test_voice_does_not_change_request(self):
        # указание «ответ озвучат» сбивает Gemma: вместо вызова пишет «Устанавливаю громкость…» (eval: 23/34 против 33/34)
        self.llama.replies = [[text("а")], [text("б")]]
        await self.ask("громче", voice=False)
        self.brain.reset()
        await self.ask("громче", voice=True)
        self.assertEqual(self.llama.bodies[0]["messages"], self.llama.bodies[1]["messages"])

    async def test_system_prompt_constant(self):
        # озвучка не меняет системный промпт — иначе llama-server пересчитывает его и инструменты (~1,5 с)
        self.llama.replies = [[text("а")], [text("б")]]
        await self.ask("привет", voice=False)
        await self.ask("привет", voice=True)
        self.assertEqual(self.llama.bodies[0]["messages"][0], self.llama.bodies[1]["messages"][0])
        self.assertEqual(self.llama.bodies[0]["tools"], self.llama.bodies[1]["tools"])


class FakeProc:
    def __init__(self, returncode=None):
        self.returncode = returncode

    def terminate(self):
        self.returncode = -15

    async def wait(self):
        return self.returncode


class ServerTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.llama = FakeLlama()
        await self.llama.start()
        self.addAsyncCleanup(self.llama.close)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        (Path(tmp.name) / "logs").mkdir()
        self.exec = AsyncMock(side_effect=lambda *a, **k: FakeProc())
        for p in (patch("glass_assistant.local.asyncio.create_subprocess_exec", self.exec),
                  patch("glass_assistant.local.shutil.which", return_value="/usr/bin/llama-server"),
                  patch("glass_assistant.local.os.path.exists", return_value=True),
                  patch("glass_assistant.config.DATA", Path(tmp.name))):
            p.start()
            self.addCleanup(p.stop)
        self.server = LocalServer(port=self.llama.port)
        self.cfg = dict(config.DEFAULTS)

    async def test_flags(self):
        await self.server.ensure(self.cfg)
        args = self.exec.await_args.args
        for flag in (["-ngl", "99"], ["-fit", "off"], ["--jinja"], ["--reasoning", "off"], ["-np", "1"], ["-c", "8192"]):
            i = args.index(flag[0])
            self.assertEqual(list(args[i:i + len(flag)]), flag)

    async def test_concurrent_ensure_one_process(self):
        await asyncio.gather(self.server.warm(self.cfg), self.server.ensure(self.cfg))
        self.assertEqual(self.exec.await_count, 1)

    async def test_fallback_to_fit_on(self):
        procs = iter([FakeProc(returncode=1), FakeProc()])
        self.exec.side_effect = lambda *a, **k: next(procs)
        await self.server.ensure(self.cfg)
        second = self.exec.await_args_list[1].args
        self.assertIn("on", second[second.index("--fit") + 1:second.index("--fit") + 2])
        self.assertNotIn("-ngl", second)

    async def test_unload(self):
        await self.server.ensure(self.cfg)
        proc = self.server.proc
        await self.server.unload()
        self.assertEqual(proc.returncode, -15)
        await self.server.ensure(self.cfg)
        self.assertEqual(self.exec.await_count, 2)


if __name__ == "__main__":
    unittest.main()
