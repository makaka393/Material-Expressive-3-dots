import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import config, tools
from glass_assistant.local import Gate, LocalBrain, LocalServer, Reply
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
        self.assertEqual(reply, Reply("Привет!", []))

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

    async def test_pseudo_call_text_retries_with_escape(self):
        # модель написала вызов текстом («power off», «suggest_claude{}») — переспрашиваем с обязательным
        # вызовом, но с выходом «подходящего нет»: иначе она хватает любой (было do_not_disturb на «открой браузер»)
        self.llama.replies = [[text("power off")], [call(0, "nothing_fits", "{}", id="n")]]
        reply = await self.ask("выключи компьютер")
        retry = self.llama.bodies[1]
        self.assertEqual(retry.get("tool_choice"), "required")
        self.assertIn("nothing_fits", [t["function"]["name"] for t in retry["tools"]])
        self.assertNotIn("nothing_fits", [t["function"]["name"] for t in self.llama.bodies[0]["tools"]])
        self.assertEqual(ran, [])
        self.assertEqual(reply.text, "Пока так не умею.")
        self.assertEqual(self.deltas, ["Пока так не умею."])

    async def test_long_pseudo_call_not_leaked(self):
        self.llama.replies = [[text('media{"act'), text('ion": "next"}')], [call(0, "volume", '{"change": 10}', id="v")]]
        await self.ask("следующий")
        self.assertEqual(self.deltas, [])
        self.assertEqual(ran, [{"change": 10}])

    async def test_empty_answer_retries(self):
        self.llama.replies = [[text("[2026-10-18 14:05, воскресенье] ")], [call(0, "volume", '{"change": 10}', id="v")]]
        await self.ask("громче")
        self.assertEqual(ran, [{"change": 10}])

    async def test_retry_without_call_says_cant(self):
        self.llama.replies = [[text("Открываю браузер.")], [text("Открываю.")]]
        reply = await self.ask("открой браузер")
        self.assertEqual(ran, [])
        self.assertEqual(reply.text, "Пока так не умею.")
        self.assertEqual(self.deltas, ["Пока так не умею."])

    async def test_cant_not_in_history_as_call(self):
        # nothing_fits нет в обычном списке инструментов — в истории только текст
        self.llama.replies = [[text("power off")], [call(0, "nothing_fits", "{}", id="n")], [text("ок")]]
        await self.ask("выключи компьютер")
        await self.ask("ладно")
        assistant = [m for m in self.llama.bodies[2]["messages"] if m["role"] == "assistant"][0]
        self.assertEqual(assistant["content"], "Пока так не умею.")
        self.assertNotIn("tool_calls", assistant)

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

    async def test_memory_in_system_prompt(self):
        from glass_assistant import memory
        m = memory.Memory(Path(tempfile.mkdtemp()) / "m.json")
        m.add("Пользователя зовут Рома")
        self.llama.replies = [[text("Рома")]]
        with patch.object(memory, "store", m):
            await self.ask("как меня зовут")
        self.assertIn("- Пользователя зовут Рома", self.llama.bodies[0]["messages"][0]["content"])

    async def test_system_prompt_constant(self):
        # озвучка не меняет системный промпт — иначе llama-server пересчитывает его и инструменты (~1,5 с)
        self.llama.replies = [[text("а")], [text("б")]]
        await self.ask("привет", voice=False)
        await self.ask("привет", voice=True)
        self.assertEqual(self.llama.bodies[0]["messages"][0], self.llama.bodies[1]["messages"][0])
        self.assertEqual(self.llama.bodies[0]["tools"], self.llama.bodies[1]["tools"])


class GateTest(unittest.TestCase):
    def run_gate(self, chunks):
        g = Gate()
        out = "".join(g.feed(c) for c in chunks) + g.flush()
        return out, g.claimed

    def test_russian_answer_with_english_word_passes(self):
        self.assertEqual(self.run_gate(["Spotify (музыкальный ", "сервис) уже играет."]),
                         ("Spotify (музыкальный сервис) уже играет.", False))

    def test_ascii_only_short_text_is_pseudo_call(self):
        for chunks in (["power off"], ["Suggest Claude"], ["suggest_claude{}"], ['media{"act', 'ion": "next"}']):
            self.assertEqual(self.run_gate(chunks), ("", True), chunks)

    def test_memory_claims_are_claims(self):
        # «Я забыл информацию о машине.» без вызова forget — пустое обещание
        for t in ("Я забыл информацию о твоей машине.", "Запомнил, тебя зовут Рома.", "Хорошо, запоминаю.",
                  "Конечно, делаю потише.", "Сделаю потише. На сколько уменьшить громкость?", "Сейчас включу."):
            self.assertEqual(self.run_gate([t]), ("", True), t)

    def test_stamp_stripped(self):
        self.assertEqual(self.run_gate(["[2026-10-18 14:05, воскресенье]\n", "Привет!"]), ("Привет!", False))


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

    async def test_fallback_chain_when_fit_crashes(self):
        # мало видеопамяти (игра, Waydroid): -ngl 99 — нехватка, --fit on иногда падает (GGML_ASSERT) —
        # тогда 8 слоёв на видеокарте, а нет — только процессор
        procs = iter([FakeProc(returncode=1), FakeProc(returncode=134), FakeProc()])
        self.exec.side_effect = lambda *a, **k: next(procs)
        await self.server.ensure(self.cfg)
        third = list(self.exec.await_args_list[2].args)
        self.assertEqual(third[third.index("-ngl") + 1], "8")

    async def test_cpu_last_resort(self):
        procs = iter([FakeProc(returncode=1)] * 3 + [FakeProc()])
        self.exec.side_effect = lambda *a, **k: next(procs)
        await self.server.ensure(self.cfg)
        last = list(self.exec.await_args_list[3].args)
        self.assertEqual(last[last.index("-ngl") + 1], "0")

    async def test_all_fail(self):
        self.exec.side_effect = lambda *a, **k: FakeProc(returncode=1)
        with self.assertRaises(RuntimeError):
            await self.server.ensure(self.cfg)

    async def test_unload(self):
        await self.server.ensure(self.cfg)
        proc = self.server.proc
        await self.server.unload()
        self.assertEqual(proc.returncode, -15)
        await self.server.ensure(self.cfg)
        self.assertEqual(self.exec.await_count, 2)


if __name__ == "__main__":
    unittest.main()
