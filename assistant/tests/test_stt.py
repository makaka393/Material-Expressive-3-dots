import unittest

import numpy as np

from glass_assistant import config
from glass_assistant.stt import FRAME, RATE, Vad, record_utterance


def frames(spec):
    """spec: [(«loud»|«quiet», секунд)] → кадры по 30 мс: речь — синус погромче, тишина — слабый шум."""
    rng = np.random.default_rng(1)
    for kind, sec in spec:
        for _ in range(int(sec * RATE / FRAME)):
            if kind == "loud":
                t = np.arange(FRAME) / RATE
                yield (np.sin(2 * np.pi * 220 * t) * 4000).astype(np.int16)
            else:
                yield (rng.normal(0, 60, FRAME)).astype(np.int16)


async def agen(it):
    for f in it:
        yield f


async def level(v, b=None):
    pass


class RecordTest(unittest.IsolatedAsyncioTestCase):
    SPEECH_WITH_PAUSE = [("quiet", 0.4), ("loud", 1.0), ("quiet", 1.0), ("loud", 1.0), ("quiet", 3.0)]

    async def test_pause_inside_phrase_does_not_cut(self):
        # «обсидиан… выкрути яркость»: секунда раздумья посреди фразы — это ещё та же фраза
        audio = await record_utterance("", level, tail=config.DEFAULTS["pause"], frames=agen(frames(self.SPEECH_WITH_PAUSE)))
        self.assertGreater(len(audio) / RATE, 2.5)

    async def test_short_pause_setting_cuts(self):
        audio = await record_utterance("", level, tail=0.8, frames=agen(frames(self.SPEECH_WITH_PAUSE)))
        self.assertLess(len(audio) / RATE, 2.2)

    async def test_default_pause(self):
        self.assertEqual(config.DEFAULTS["pause"], 2.0)

    async def test_silence_only(self):
        self.assertIsNone(await record_utterance("", level, max_wait=0.5, frames=agen(frames([("quiet", 2.0)]))))

    async def test_level_with_spectrum_every_frame(self):
        # свет острова: громкость и доли четырёх полос — на каждый кадр (30 мс), пока слушает
        got = []

        async def on_level(v, b=None):
            got.append((v, b))
        await record_utterance("", on_level, tail=0.5, frames=agen(frames([("quiet", 0.3), ("loud", 0.6), ("quiet", 1.0)])))
        self.assertGreaterEqual(len(got), 45)                 # каждый кадр до конца записи (~47), а не через один
        self.assertTrue(all(len(b) == 4 and abs(sum(b) - 1) < 0.02 for _, b in got))
        self.assertGreater(max(v for v, _ in got), 0.05)


if __name__ == "__main__":
    unittest.main()


class VadMinTest(unittest.TestCase):
    def test_min_level_cuts_far_voice(self):
        # ближний режим: голос из другого конца комнаты (700) — не речь, у микрофона (1500) — речь
        default, near = Vad(), Vad(min_level=config.NEAR_MIN)
        for _ in range(60):
            default.speech(30.0)
            near.speech(30.0)
        self.assertTrue(default.speech(700.0))
        self.assertFalse(near.speech(700.0))
        self.assertTrue(near.speech(config.NEAR_MIN + 600))
