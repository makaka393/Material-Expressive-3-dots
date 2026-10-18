import unittest

import numpy as np

from glass_assistant import config
from glass_assistant.stt import FRAME, RATE, record_utterance


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


async def level(v):
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
        self.assertEqual(config.DEFAULTS["pause"], 1.3)

    async def test_silence_only(self):
        self.assertIsNone(await record_utterance("", level, max_wait=0.5, frames=agen(frames([("quiet", 2.0)]))))


if __name__ == "__main__":
    unittest.main()
