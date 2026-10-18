import json
import unittest
from unittest.mock import AsyncMock, patch

from glass_assistant import tools
from glass_assistant.tools import base
from glass_assistant.tools.base import Result

CLIENTS = [{"address": "0x1", "class": "zen", "title": "YouTube", "workspace": {"id": 1}},
           {"address": "0x2", "class": "discord", "title": "Discord", "workspace": {"id": 2}},
           {"address": "0x3", "class": "discord", "title": "Discord popout", "workspace": {"id": 2}},
           {"address": "0x4", "class": "kitty", "title": "~", "workspace": {"id": 3}}]


class HyprFake:
    """hyprctl понарошку: фокус по адресу меняет активное окно, всё записывается."""

    def __init__(self, active="0x4", workspace=3, focus_works=True):
        self.active, self.workspace, self.focus_works = active, workspace, focus_works
        self.calls = []

    async def sh(self, *argv, timeout=5):
        self.calls.append(argv)
        if argv[:3] == ("hyprctl", "clients", "-j"):
            return json.dumps(CLIENTS)
        if argv[:3] == ("hyprctl", "activewindow", "-j"):
            w = next((c for c in CLIENTS if c["address"] == self.active), None)
            return json.dumps(w or {})
        if argv[:3] == ("hyprctl", "activeworkspace", "-j"):
            return json.dumps({"id": self.workspace})
        if argv[:2] == ("hyprctl", "dispatch"):
            lua = argv[2]
            if lua.startswith('hl.dsp.focus({ window = "address:') and self.focus_works:
                self.active = lua.split("address:")[1].split('"')[0]
            elif lua.startswith("hl.dsp.focus({ workspace = "):
                self.workspace = lua.split("= ")[1].split(" ")[0]
        return "ok"

    def dispatched(self):
        return [a[2] for a in self.calls if a[:2] == ("hyprctl", "dispatch")]

    def keys(self):
        return [a[1:] for a in self.calls if a[0] == "wtype"]


class WindowsTest(unittest.IsolatedAsyncioTestCase):
    def use(self, **kw):
        self.h = HyprFake(**kw)
        for p in (patch.object(base, "sh", self.h.sh), patch.object(base, "qs", AsyncMock(return_value=""))):
            p.start()
            self.addCleanup(p.stop)

    async def test_close_active_window(self):
        self.use()
        r = await tools.run("window", {"action": "close"})
        self.assertEqual(self.h.dispatched(), ["hl.dsp.window.close()"])
        self.assertTrue(r.ok)

    async def test_no_active_window(self):
        self.use(active=None)
        r = await tools.run("window", {"action": "fullscreen"})
        self.assertFalse(r.ok)
        self.assertEqual(self.h.dispatched(), [])

    async def test_fullscreen_float_pin(self):
        self.use()
        for action, lua in (("fullscreen", "hl.dsp.window.fullscreen()"), ("float", 'hl.dsp.window.float({ action = "toggle" })'),
                            ("pin", "hl.dsp.window.pin()")):
            await tools.run("window", {"action": action})
            self.assertEqual(self.h.dispatched()[-1], lua)

    async def test_app_window_focus_then_act_then_back(self):
        # ключ window = … в Lua-диспетчерах Hyprland молча игнорирует и бьёт по активному окну —
        # поэтому сначала фокус на нужное окно, проверка, действие, и обратно на свой стол
        self.use()
        r = await tools.run("close_app", {"name": "дискорд"})
        self.assertEqual(self.h.dispatched(), [
            'hl.dsp.focus({ window = "address:0x2" })', "hl.dsp.window.close()",
            'hl.dsp.focus({ window = "address:0x3" })', "hl.dsp.window.close()",
            "hl.dsp.focus({ workspace = 3 })"])
        self.assertTrue(r.ok)

    async def test_focus_failed_does_nothing(self):
        self.use(focus_works=False)
        r = await tools.run("close_app", {"name": "дискорд"})
        self.assertNotIn("hl.dsp.window.close()", self.h.dispatched())
        self.assertFalse(r.ok)

    async def test_move_window(self):
        self.use()
        await tools.run("move_window", {"workspace": 5})
        self.assertEqual(self.h.dispatched(), ["hl.dsp.window.move({ workspace = 5 })"])

    async def test_workspace_number_and_next(self):
        self.use()
        await tools.run("workspace", {"number": 2})
        await tools.run("workspace", {"direction": "next"})
        self.assertEqual(self.h.dispatched(), ["hl.dsp.focus({ workspace = 2 })", 'hl.dsp.focus({ workspace = "e+1" })'])

    async def test_browser_tab_next_focuses_browser_first(self):
        self.use()                                         # активен kitty, браузер — 0x1
        r = await tools.run("browser_tab", {"action": "next"})
        self.assertEqual(self.h.dispatched(), ['hl.dsp.focus({ window = "address:0x1" })'])
        base.qs.assert_awaited_with("launcher", "close")   # лаунчер держит клавиатуру — закрыть
        self.assertEqual(self.h.keys(), [("-M", "ctrl", "-k", "Tab", "-m", "ctrl")])
        self.assertEqual(r, Result(True, "Следующая вкладка"))

    async def test_browser_tab_keys(self):
        self.use(active="0x1")
        cases = {"previous": ("-M", "ctrl", "-M", "shift", "-k", "Tab", "-m", "shift", "-m", "ctrl"),
                 "new": ("-M", "ctrl", "-k", "t", "-m", "ctrl"), "close": ("-M", "ctrl", "-k", "w", "-m", "ctrl"),
                 "reopen": ("-M", "ctrl", "-M", "shift", "-k", "t", "-m", "shift", "-m", "ctrl"),
                 "back": ("-M", "alt", "-k", "Left", "-m", "alt"), "reload": ("-k", "F5",)}
        for action, keys in cases.items():
            await tools.run("browser_tab", {"action": action})
            self.assertEqual(self.h.keys()[-1], keys, action)
        await tools.run("browser_tab", {"action": "number", "number": 3})
        self.assertEqual(self.h.keys()[-1], ("-M", "ctrl", "-k", "3", "-m", "ctrl"))
        self.assertEqual(self.h.dispatched(), [])          # браузер уже активен — фокус не трогаем

    async def test_browser_tab_no_browser(self):
        self.use(active="0x4")
        with patch("glass_assistant.tools.windows.BROWSERS", {"firefox"}):
            r = await tools.run("browser_tab", {"action": "next"})
        self.assertFalse(r.ok)
        self.assertEqual(self.h.keys(), [])

    async def test_browser_tab_focus_failed_no_keys(self):
        self.use(focus_works=False)
        r = await tools.run("browser_tab", {"action": "next"})
        self.assertFalse(r.ok)
        self.assertEqual(self.h.keys(), [])                # не печатать в чужое окно


if __name__ == "__main__":
    unittest.main()
