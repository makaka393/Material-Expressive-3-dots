import unittest
from unittest.mock import AsyncMock, patch

from glass_assistant import config
from glass_assistant.tts import Voice


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
        self.assertEqual(v.queue.get_nowait(), (0, "Привет", ("baya", "high", "slow")))

    def test_defaults(self):
        self.assertEqual((config.DEFAULTS["voice_pitch"], config.DEFAULTS["voice_rate"]), ("medium", "medium"))


if __name__ == "__main__":
    unittest.main()
