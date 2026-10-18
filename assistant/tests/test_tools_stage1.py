import unittest
from unittest.mock import AsyncMock, call, patch

from glass_assistant import tools
from glass_assistant.tools.base import Result

SINK = "@DEFAULT_AUDIO_SINK@"


class Stage1Test(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.sh = AsyncMock(return_value="")
        self.qs = AsyncMock(return_value="")
        for name, mock in (("sh", self.sh), ("qs", self.qs)):
            p = patch(f"glass_assistant.tools.base.{name}", mock)
            p.start()
            self.addCleanup(p.stop)

    async def test_media_toggle(self):
        r = await tools.run("media", {"action": "toggle"})
        self.sh.assert_awaited_once_with("playerctl", "play-pause")
        self.assertEqual(r, Result(True, "Пауза/продолжить"))

    async def test_media_next(self):
        r = await tools.run("media", {"action": "next"})
        self.sh.assert_awaited_once_with("playerctl", "next")
        self.assertEqual(r, Result(True, "Следующий трек"))

    async def test_media_seek_forward(self):
        await tools.run("media", {"action": "seek_forward", "seconds": 30})
        self.sh.assert_awaited_once_with("playerctl", "position", "30+")

    async def test_media_seek_back_default(self):
        await tools.run("media", {"action": "seek_back"})
        self.sh.assert_awaited_once_with("playerctl", "position", "10-")

    async def test_media_no_player(self):
        self.sh.side_effect = RuntimeError("No players found")
        r = await tools.run("media", {"action": "next"})
        self.assertEqual(r, Result(False, "Не получилось: плеер не запущен"))

    async def test_volume_change(self):
        self.sh.side_effect = ["", "Volume: 0.40"]
        r = await tools.run("volume", {"change": 10})
        self.assertEqual(self.sh.await_args_list, [call("wpctl", "set-volume", "-l", "1.0", SINK, "10%+"),
                                                   call("wpctl", "get-volume", SINK)])
        self.assertEqual(r, Result(True, "Громкость 40%"))

    async def test_volume_down(self):
        self.sh.side_effect = ["", "Volume: 0.25 [MUTED]"]
        await tools.run("volume", {"change": -15})
        self.assertEqual(self.sh.await_args_list[0], call("wpctl", "set-volume", "-l", "1.0", SINK, "15%-"))

    async def test_volume_level(self):
        self.sh.side_effect = ["", "Volume: 0.30"]
        await tools.run("volume", {"level": 30})
        self.assertEqual(self.sh.await_args_list[0], call("wpctl", "set-volume", "-l", "1.0", SINK, "30%"))

    async def test_volume_mute(self):
        r = await tools.run("volume", {"mute": True})
        self.sh.assert_awaited_once_with("wpctl", "set-mute", SINK, "1")
        self.assertEqual(r, Result(True, "Звук выключен"))

    async def test_volume_nothing(self):
        r = await tools.run("volume", {})
        self.assertFalse(r.ok)
        self.sh.assert_not_awaited()

    async def test_brightness_change(self):
        self.qs.return_value = "60"
        r = await tools.run("brightness", {"change": -20})
        self.qs.assert_awaited_once_with("brightness", "change", -20)
        self.assertEqual(r, Result(True, "Яркость 60%"))

    async def test_brightness_level(self):
        self.qs.return_value = "100"
        await tools.run("brightness", {"level": 100})
        self.qs.assert_awaited_once_with("brightness", "set", 100)

    async def test_night_light(self):
        r = await tools.run("night_light", {"on": True})
        self.qs.assert_awaited_once_with("night", "enable")
        self.assertEqual(r, Result(True, "Ночной режим включён"))

    async def test_dnd_off(self):
        r = await tools.run("do_not_disturb", {"on": False})
        self.qs.assert_awaited_once_with("notifs", "set", "false")
        self.assertEqual(r, Result(True, "«Не беспокоить» выключено"))

    def test_no_suggest_tool(self):
        # «спроси у Claude» от локальной модели раздражал: она так отвечала на всё подряд
        self.assertNotIn("suggest_claude", tools.TOOLS)


if __name__ == "__main__":
    unittest.main()
