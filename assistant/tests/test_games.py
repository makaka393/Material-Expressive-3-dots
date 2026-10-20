"""Игровой режим: пока идёт игра (метка $XDG_RUNTIME_DIR/glass-game), Whisper и локальная модель выгружены
и не грузятся, голосом Вега не слушает, а Claude («морковь») и таймеры работают."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import config, games
from glass_assistant.daemon import Daemon
from glass_assistant.local import LocalServer
from glass_assistant.stt import Whisper
from tests.test_daemon import FakeBrain


class GameTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        cfg = {**config.DEFAULTS, "speak_voice": False, "speak_typed": False, "wake": True}
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.mark = Path(tmp.name) / "glass-game"
        for p in (patch("glass_assistant.config.load", return_value=cfg),
                  patch("glass_assistant.config.has_key", return_value=True),
                  patch("glass_assistant.games.MARK", self.mark),
                  patch("glass_assistant.games.playing", False)):
            p.start()
            self.addCleanup(p.stop)
        self.d = Daemon()
        self.d.local_brain = FakeBrain("локально")
        self.d.claude_brain = FakeBrain("от Claude")
        self.d.local = AsyncMock()
        self.d.whisper = AsyncMock()
        self.events = []

        async def emit(ev, **kw):
            self.events.append((ev, kw))
        self.d.emit = emit

    def ev(self, name):
        return [kw for e, kw in self.events if e == name]

    async def start_game(self):
        self.mark.touch()
        await self.d.game_tick()

    async def test_game_start_unloads_models(self):
        await self.start_game()
        self.assertTrue(games.playing)
        self.d.local.unload.assert_awaited_once()
        self.d.whisper.stop.assert_awaited_once()

    async def test_game_end(self):
        await self.start_game()
        self.mark.unlink()
        await self.d.game_tick()
        self.assertFalse(games.playing)
        self.assertFalse(self.d._wake_paused())

    async def test_tick_without_change_does_nothing(self):
        await self.d.game_tick()
        self.d.local.unload.assert_not_awaited()
        await self.start_game()
        await self.d.game_tick()
        self.d.local.unload.assert_awaited_once()

    async def test_no_wake_word_while_gaming(self):
        # слово-активатор гонял Whisper на звуке игры — до целого ядра процессора
        self.assertFalse(self.d._wake_paused())
        await self.start_game()
        self.assertTrue(self.d._wake_paused())

    async def test_voice_refused_while_gaming(self):
        await self.start_game()
        with patch.object(self.d, "on_call") as call:
            await self.d.command({"cmd": "listen"})
        call.assert_not_called()                     # музыку не приглушаем, микрофон не открываем
        self.assertFalse(self.d.busy())
        self.assertIn("игра", self.ev("error")[-1]["text"])

    async def test_local_question_refused_without_claude(self):
        # на время игры локальная модель «умерла»; сама к Claude вопрос не уходит
        await self.start_game()
        await self.d.command({"cmd": "ask", "text": "привет"})
        await self.d.job
        self.assertEqual(self.d.local_brain.asked, [])
        self.assertEqual(self.d.claude_brain.asked, [])
        self.assertIn("игра", self.ev("error")[-1]["text"])

    async def test_claude_still_answers_while_gaming(self):
        await self.start_game()
        await self.d.ask("морковь, что такое кварк")
        self.assertEqual(self.d.claude_brain.asked, ["что такое кварк"])

    async def test_warm_ignored_while_gaming(self):
        await self.start_game()
        await self.d.command({"cmd": "warm"})
        self.d.local.warm.assert_not_called()


class ServersRefuseTest(unittest.IsolatedAsyncioTestCase):
    async def test_models_do_not_start_while_gaming(self):
        with patch("glass_assistant.games.playing", True):
            with self.assertRaises(games.Gaming):
                await LocalServer().ensure(dict(config.DEFAULTS))
            with self.assertRaises(games.Gaming):
                await Whisper().ensure(dict(config.DEFAULTS))
