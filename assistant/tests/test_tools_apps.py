import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import tools
from glass_assistant.tools import apps, base
from glass_assistant.tools.base import Result

DESKTOP = {
    "org.telegram.desktop.desktop": "Name=Telegram\nComment=Messenger\nExec=Telegram -- %u\nStartupWMClass=TelegramDesktop\n",
    "discord.desktop": "Name=Discord\nGenericName=Internet Messenger\nExec=/usr/bin/discord\n",
    "steam.desktop": "Name=Steam\nExec=/usr/bin/steam %U\n",
    "spotify.desktop": "Name=Spotify\nGenericName=Music Player\nExec=spotify %U\nKeywords=music;\n",
    "zen.desktop": "Name=Zen Browser\nGenericName=Web Browser\nGenericName[ru]=Веб-браузер\nExec=zen %u\n",
    "kitty.desktop": "Name=kitty\nGenericName=Terminal emulator\nExec=kitty\n",
    "thunar.desktop": "Name=Thunar File Manager\nName[ru]=Файловый менеджер Thunar\nExec=thunar %F\n",
    "vlc.desktop": "Name=VLC media player\nName[ru]=Медиаплеер VLC\nExec=/usr/bin/vlc %U\n",
    "hidden.desktop": "Name=Secret\nExec=secret\nNoDisplay=true\n",
}


class AppsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        d = Path(tmp.name)
        for name, body in DESKTOP.items():
            (d / name).write_text("[Desktop Entry]\nType=Application\n" + body)
        self.clients = []
        self.calls = []

        async def sh(*argv, timeout=5):
            self.calls.append(argv)
            if argv[:3] == ("hyprctl", "clients", "-j"):
                return json.dumps(self.clients)
            if argv[:3] == ("xdg-settings", "get", "default-web-browser"):
                return "zen.desktop"
            return "ok"
        for p in (patch.object(apps, "DIRS", [d]), patch.object(base, "sh", sh), patch.object(base, "qs", AsyncMock(return_value=""))):
            p.start()
            self.addCleanup(p.stop)

    def dispatched(self):
        return [a[2] for a in self.calls if a[:2] == ("hyprctl", "dispatch")]

    def test_find(self):
        for q, want in [("Telegram", "org.telegram.desktop"), ("телеграм", "org.telegram.desktop"),
                        ("телегу", "org.telegram.desktop"), ("тг", "org.telegram.desktop"), ("дискорд", "discord"),
                        ("стим", "steam"), ("спотифай", "spotify"), ("музыку", "spotify"), ("терминал", "kitty"),
                        ("проводник", "thunar"), ("файловый менеджер", "thunar"), ("медиаплеер", "vlc"), ("влц", "vlc")]:
            e = apps.find(q)
            self.assertEqual(e.id if e else None, want, q)
        self.assertIsNone(apps.find("фотошоп"))
        self.assertIsNone(apps.find("secret"))                       # NoDisplay

    async def test_open_launches_through_hyprland(self):
        # не из службы: при её перезапуске systemd убил бы и открытое приложение
        r = await tools.run("open_app", {"name": "телега"})
        self.assertEqual(r, Result(True, "Открываю Telegram"))
        self.assertEqual(self.dispatched(), ['hl.dsp.exec_cmd("gtk-launch org.telegram.desktop")'])

    async def test_open_running_focuses(self):
        self.clients = [{"address": "0x1", "class": "TelegramDesktop", "title": "Telegram", "workspace": {"id": 5}}]
        r = await tools.run("open_app", {"name": "телеграм"})
        self.assertEqual(r, Result(True, "Показываю Telegram"))
        self.assertEqual(self.dispatched(), ['hl.dsp.focus({ window = "address:0x1" })'])

    async def test_browser_is_default(self):
        r = await tools.run("open_app", {"name": "браузер"})
        self.assertEqual(r.show, "Открываю Zen Browser")

    async def test_settings_are_shell_settings(self):
        r = await tools.run("open_app", {"name": "настройки"})
        base.qs.assert_awaited_once_with("settings", "open")
        self.assertTrue(r.ok)

    async def test_open_unknown(self):
        r = await tools.run("open_app", {"name": "фотошоп"})
        self.assertFalse(r.ok)
        self.assertEqual(r.say, "Не нашёл приложение «фотошоп».")

    async def test_close_app(self):
        self.clients = [{"address": "0x1", "class": "discord", "title": "Discord", "workspace": {"id": 2}},
                        {"address": "0x2", "class": "kitty", "title": "~", "workspace": {"id": 3}},
                        {"address": "0x3", "class": "discord", "title": "Discord popout", "workspace": {"id": 2}}]
        r = await tools.run("close_app", {"name": "дискорд"})
        self.assertEqual(self.dispatched(), ['hl.dsp.window.close({ window = "address:0x1" })',
                                             'hl.dsp.window.close({ window = "address:0x3" })'])
        self.assertEqual(r, Result(True, "Закрываю Discord"))

    async def test_close_app_without_windows(self):
        r = await tools.run("close_app", {"name": "стим"})
        self.assertEqual(r, Result(False, "Окна «Steam» нет", "Окна «Steam» нет."))
        self.assertEqual(self.dispatched(), [])

    async def test_open_url(self):
        await tools.run("open_url", {"url": "github.com/makaka393"})
        self.assertEqual(self.dispatched(), ['hl.dsp.exec_cmd("xdg-open https://github.com/makaka393")'])

    async def test_open_url_rejects_other_schemes(self):
        r = await tools.run("open_url", {"url": "file:///etc/passwd"})
        self.assertFalse(r.ok)
        self.assertEqual(self.dispatched(), [])

    async def test_web_search(self):
        await tools.run("web_search", {"query": "как сделать пиццу", "site": "youtube"})
        self.assertEqual(self.dispatched(), [
            'hl.dsp.exec_cmd("xdg-open \'https://www.youtube.com/results?search_query=%D0%BA%D0%B0%D0%BA+'
            '%D1%81%D0%B4%D0%B5%D0%BB%D0%B0%D1%82%D1%8C+%D0%BF%D0%B8%D1%86%D1%86%D1%83\'")'])

    async def test_lua_and_shell_quoting(self):
        await base.launch("echo", 'a"b', "c d")
        self.assertEqual(self.dispatched(), ['hl.dsp.exec_cmd("echo \'a\\"b\' \'c d\'")'])


if __name__ == "__main__":
    unittest.main()
