import unittest
import asyncio
from unittest.mock import AsyncMock, patch

from glass_assistant import config
from glass_assistant.tts import Sentences, Voice


class FakeAudio:
    def numpy(self):
        import numpy as np
        return np.zeros(10, dtype="float32")


class FakeModel:
    def __init__(self):
        self.calls = []

    def apply_tts(self, **kw):
        self.calls.append(kw)
        return FakeAudio()


class SynthTest(unittest.TestCase):
    def setUp(self):
        self.v = Voice()
        self.v.model = FakeModel()

    def test_plain_text_by_default(self):
        self.v._synth("Привет.", ("xenia", "medium", "medium"))
        kw = self.v.model.calls[0]
        self.assertEqual((kw["text"], kw["speaker"]), ("Привет.", "xenia"))
        self.assertNotIn("ssml_text", kw)

    def test_pitch_and_rate_via_ssml(self):
        self.v._synth("Ты & я <3", ("aidar", "low", "fast"))
        kw = self.v.model.calls[0]
        self.assertEqual(kw["ssml_text"], '<speak><prosody pitch="low" rate="fast">Ты &amp; я &lt;3</prosody></speak>')
        self.assertEqual(kw["speaker"], "aidar")
        self.assertNotIn("text", kw)


class SayTest(unittest.IsolatedAsyncioTestCase):
    async def test_say_queues_voice_settings(self):
        v = Voice()
        v.ready = AsyncMock()
        cfg = {**config.DEFAULTS, "voice": "baya", "voice_pitch": "high", "voice_rate": "slow"}
        await v.say("Привет", cfg)
        self.assertEqual(v.texts.get_nowait(), (0, "Привет", ("baya", "high", "slow")))

    def test_defaults(self):
        self.assertEqual((config.DEFAULTS["voice_pitch"], config.DEFAULTS["voice_rate"]), ("medium", "medium"))


class FakeStdin:
    def __init__(self, log):
        self.log = log

    def write(self, b):
        self.log.append(("write", len(b)))

    async def drain(self):
        await asyncio.sleep(0)

    def close(self):
        self.log.append("close")


class FakeProc:
    def __init__(self, log):
        self.log, self.returncode = log, None
        self.stdin = FakeStdin(log)

    async def wait(self):
        self.log.append("exit")
        self.returncode = 0
        return 0

    def terminate(self):
        self.log.append("kill")
        self.returncode = -15


class PlayerTest(unittest.IsolatedAsyncioTestCase):
    """Один процесс проигрывания на весь ответ: без паузы на запуск pw-play перед каждой фразой."""

    async def asyncSetUp(self):
        self.log = []
        self.spawned = 0

        async def spawn():
            self.spawned += 1
            self.log.append("spawn")
            return FakeProc(self.log)
        self.v = Voice(spawn=spawn)
        self.v.model = FakeModel()
        self.cfg = {**config.DEFAULTS}

    async def test_sentences_share_one_player(self):
        await self.v.say("Первая фраза.", self.cfg)
        await self.v.say("Вторая фраза.", self.cfg)
        await asyncio.wait_for(self.v.idle.wait(), 3)
        self.assertEqual(self.spawned, 1)
        self.assertEqual([x for x in self.log if isinstance(x, str)], ["spawn", "close", "exit"])
        self.assertEqual(len([x for x in self.log if isinstance(x, tuple)]), 2)

    async def test_stop_kills_and_next_answer_respawns(self):
        await self.v.say("Длинная фраза.", self.cfg)
        await asyncio.sleep(0.05)
        self.v.stop()
        self.assertTrue(self.v.idle.is_set())
        self.assertIn("kill", self.log)
        await self.v.say("Новая.", self.cfg)
        await asyncio.wait_for(self.v.idle.wait(), 3)
        self.assertEqual(self.spawned, 2)

    async def test_ready_preloads_and_warms(self):
        v = Voice(spawn=AsyncMock())
        with patch.object(Voice, "_load", lambda self, path: FakeModel()):
            await v.ready(self.cfg)
        self.assertEqual(len(v.model.calls), 1)               # разогрев: первый синтез после загрузки медленный


class SentencesTest(unittest.TestCase):
    def test_first_piece_at_comma(self):
        # первую реплику — по первой запятой: звук пойдёт раньше, чем модель допишет длинное предложение
        s = Sentences()
        self.assertEqual(s.feed("Небо кажется синим из-за того, что атмосфера "), ["Небо кажется синим из-за того,"])
        self.assertEqual(s.feed("рассеивает синий свет сильнее, чем красный. Дальше"),
                         ["что атмосфера рассеивает синий свет сильнее, чем красный."])
        self.assertEqual(s.flush(), ["Дальше"])

    def test_short_first_clause_waits(self):
        s = Sentences()
        self.assertEqual(s.feed("Да, конечно"), [])


if __name__ == "__main__":
    unittest.main()
