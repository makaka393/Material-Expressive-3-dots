import unittest
import asyncio
from unittest.mock import AsyncMock, patch

from glass_assistant import config
from glass_assistant.tts import Sentences, Voice, prosody, shape, speakable, voice_of


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
        self.v._synth("Привет.", ("xenia", 0.0, 1.0, 0.0))
        kw = self.v.model.calls[0]
        self.assertEqual((kw["text"], kw["speaker"]), ("Привет.", "xenia"))
        self.assertNotIn("ssml_text", kw)

    def test_speed_and_height_via_ssml_percent(self):
        # Silero принимает проценты: pitch="+15%", rate="120%" — ползунки плавные, не 3 ступеньки
        self.v._synth("Ты & я <3", ("aidar", 0.0, 1.2, 1.0))
        kw = self.v.model.calls[0]
        self.assertEqual(kw["ssml_text"], '<speak><prosody pitch="+15%" rate="120%">Ты &amp; я &lt;3</prosody></speak>')
        self.assertEqual(kw["speaker"], "aidar")
        self.assertNotIn("text", kw)


class ProsodyTest(unittest.TestCase):
    def test_neutral(self):
        self.assertEqual(prosody(0, 1.0, 0), (0, 100))

    def test_tone_moves_pitch_and_rate_a_little(self):
        soft, firm = prosody(-1, 1.0, 0), prosody(1, 1.0, 0)
        self.assertGreater(soft[0], 0)                 # мягкий — чуть выше и неспешнее
        self.assertLess(soft[1], 100)
        self.assertLess(firm[0], 0)                    # твёрдый — ниже и быстрее
        self.assertGreater(firm[1], 100)
        self.assertLessEqual(abs(soft[0]), 5)

    def test_voice_of_clamps_and_survives_old_values(self):
        cfg = {**config.DEFAULTS, "voice": "baya", "voice_tone": 7, "voice_speed": "fast", "voice_height": -0.5}
        self.assertEqual(voice_of(cfg), ("baya", 1.0, 1.0, -0.5))


class ShapeTest(unittest.TestCase):
    """Ползунок «тон»: мягче — меньше верха, твёрже — больше присутствия и ровнее громкость."""

    def setUp(self):
        import numpy as np
        rng = np.random.default_rng(3)
        t = np.arange(48000) / 48000
        env = 0.2 + 0.8 * (np.sin(2 * np.pi * 3 * t) > 0)          # слоги: громко-тихо
        self.np = np
        self.x = ((np.sin(2 * np.pi * 180 * t) + 0.3 * rng.standard_normal(len(t))) * env * 0.3).astype("float32")

    def band(self, y, lo, hi):
        f = self.np.fft.rfftfreq(len(y), 1 / 48000)
        p = self.np.abs(self.np.fft.rfft(y)) ** 2
        return p[(f >= lo) & (f < hi)].sum() / p.sum()

    def test_neutral_untouched(self):
        self.assertIs(shape(self.x, 0.0), self.x)

    def test_soft_darker(self):
        self.assertLess(self.band(shape(self.x, -1), 4000, 12000), self.band(self.x, 4000, 12000) * 0.6)

    def test_firm_brighter_and_denser(self):
        np = self.np
        y = shape(self.x, 1)
        self.assertGreater(self.band(y, 2000, 4000), self.band(self.x, 2000, 4000) * 1.4)
        def spread(a):                                   # громкие слоги к тихим, по окнам 50 мс
            w = np.sqrt(np.mean(a[:len(a) // 2400 * 2400].astype(float).reshape(-1, 2400) ** 2, axis=1))
            return np.percentile(w, 90) / np.percentile(w, 10)
        self.assertLess(spread(y), spread(self.x) * 0.8)

    def test_level_kept(self):
        np = self.np
        rms = lambda a: float(np.sqrt(np.mean(a.astype(float) ** 2)))
        for t in (-1, -0.5, 0.5, 1):
            y = shape(self.x, t)
            self.assertEqual(y.dtype, np.float32)
            self.assertAlmostEqual(rms(y) / rms(self.x), 1.0, delta=0.12, msg=t)
            self.assertLessEqual(np.abs(y).max(), 0.971)


class SpeakableTest(unittest.TestCase):
    """Silero молча выбрасывает латиницу, а фраза из одной латиницы не звучала вовсе."""

    def test_no_latin_left(self):
        for t in ("Hi! This is how I will answer you.", "Linkin Park — Numb", "Включаю Spotify.", "RTX греется"):
            self.assertNotRegex(speakable(t), "[A-Za-z]", t)

    def test_known_words(self):
        self.assertEqual(speakable("Включаю Spotify."), "Включаю спотифай.")
        self.assertIn("клод", speakable("Claude недоступен"))
        self.assertIn("ар-ти-экс", speakable("RTX 4070"))

    def test_name_stress(self):
        self.assertEqual(speakable("Привет! Я Вега."), "Привет! Я В+ега.")


class SayTest(unittest.IsolatedAsyncioTestCase):
    async def test_say_queues_voice_settings(self):
        v = Voice()
        v.ready = AsyncMock()
        cfg = {**config.DEFAULTS, "voice": "baya", "voice_tone": -0.5, "voice_speed": 1.1, "voice_height": 0.25}
        await v.say("Привет", cfg)
        self.assertEqual(v.texts.get_nowait(), (0, "Привет", ("baya", -0.5, 1.1, 0.25)))

    def test_defaults(self):
        self.assertEqual((config.DEFAULTS["voice_tone"], config.DEFAULTS["voice_speed"], config.DEFAULTS["voice_height"]),
                         (0.0, 1.0, 0.0))


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


class VoicesTest(unittest.IsolatedAsyncioTestCase):
    def test_registry(self):
        self.assertEqual(config.voice("lessac").lang, "en")
        self.assertTrue(config.voice("alba").female)
        self.assertFalse(config.voice("ryan").female)
        self.assertEqual(config.voice("нет-такого"), config.VOICES["xenia"])
        self.assertEqual(config.voice_id({"voice": "нет-такого"}), "xenia")

    def test_english_kept_english(self):
        self.assertEqual(speakable("Hi! I'm Vega, 3 tracks.", "piper", "en"), "Hi! I'm Vega, 3 tracks.")
        self.assertNotIn("+", speakable("Я Вега.", "piper", "ru"))      # русский Piper — без ударений Silero

    async def test_russian_phrase_of_english_voice_goes_to_silero(self):
        v = Voice()
        v.ready = AsyncMock()
        cfg = {**config.DEFAULTS, "voice": "ryan"}
        with patch("glass_assistant.config.voice_id", return_value="ryan"):
            await v.say("Громкость 35 процентов", cfg)
            await v.say("Volume is 35 percent", cfg)
        self.assertEqual(v.texts.get_nowait()[2][0], "aidar")      # мужской английский → мужской Silero
        self.assertEqual(v.texts.get_nowait()[2][0], "ryan")


class LevelTest(unittest.IsolatedAsyncioTestCase):
    """Пока говорит — громкость речи по 30 мс уходит в on_level (свет острова дышит её голосом)."""

    async def test_levels_follow_audio(self):
        import numpy as np
        v = Voice()
        got = []

        async def on_level(x):
            got.append(x)
        v.on_level = on_level
        t = np.arange(4800) / 48000                       # 0,1 с: громко, потом тихо
        pcm = np.concatenate([np.sin(2 * np.pi * 200 * t) * 0.2, np.zeros(4800)]).astype("float32").tobytes()
        v._levels(pcm, v.gen, 0.0)
        await asyncio.sleep(0.35)
        self.assertGreaterEqual(len(got), 6)
        self.assertGreater(got[0], 0.3)
        self.assertLess(got[-1], 0.05)

    async def test_stop_cuts_levels(self):
        import numpy as np
        v = Voice()
        got = []

        async def on_level(x):
            got.append(x)
        v.on_level = on_level
        v._levels(np.full(48000, 0.2, dtype="float32").tobytes(), v.gen, 0.0)
        await asyncio.sleep(0.1)
        v.stop()
        n = len(got)
        await asyncio.sleep(0.2)
        self.assertLessEqual(len(got), n + 1)

