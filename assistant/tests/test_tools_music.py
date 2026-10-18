import os
import unittest
from unittest.mock import AsyncMock, patch

from glass_assistant import tools
from glass_assistant.tools import base, media

KEYS = {"SPOTIFY_CLIENT_ID": "id", "SPOTIFY_CLIENT_SECRET": "secret"}


class MusicTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.calls = []
        self.players = "spotify"

        async def sh(*argv, timeout=5):
            self.calls.append(argv)
            if argv[:2] == ("playerctl", "-l"):
                return self.players
            return ""
        self.launch = AsyncMock(return_value="ok")
        for p in (patch.object(base, "sh", sh), patch.object(base, "launch", self.launch),
                  patch.object(media, "WAIT", 0.01)):
            p.start()
            self.addCleanup(p.stop)

    async def test_with_keys_searches_and_plays(self):
        search = AsyncMock(return_value={"uri": "spotify:track:42", "name": "Numb", "by": "Linkin Park"})
        with patch.dict(os.environ, KEYS), patch.object(media, "search", search):
            r = await tools.run("play_music", {"query": "numb", "kind": "track"})
        search.assert_awaited_once_with("numb", "track")
        self.assertIn(("playerctl", "-p", "spotify", "open", "spotify:track:42"), self.calls)
        self.assertEqual(r.show, "Включаю Numb — Linkin Park")

    async def test_kind_any_is_track(self):
        search = AsyncMock(return_value={"uri": "spotify:track:1", "name": "x", "by": ""})
        with patch.dict(os.environ, KEYS), patch.object(media, "search", search):
            await tools.run("play_music", {"query": "кино"})
        search.assert_awaited_once_with("кино", "track")

    async def test_not_found(self):
        with patch.dict(os.environ, KEYS), patch.object(media, "search", AsyncMock(return_value=None)):
            r = await tools.run("play_music", {"query": "ыыыы"})
        self.assertFalse(r.ok)
        self.assertEqual(r.say, "Не нашёл «ыыыы» в Spotify.")

    async def test_without_keys_uses_wikidata(self):
        # «включи металлику» без ключей Spotify: Spotify ID исполнителя — из Wikidata
        wd = AsyncMock(return_value={"uri": "spotify:artist:2ye2", "name": "Metallica", "by": ""})
        with patch.dict(os.environ, {}, clear=True), patch.object(media, "wikidata", wd):
            r = await tools.run("play_music", {"query": "Металлика", "kind": "artist"})
        wd.assert_awaited_once_with("Металлика", "artist")
        self.assertIn(("playerctl", "-p", "spotify", "open", "spotify:artist:2ye2"), self.calls)
        self.assertEqual(r.show, "Включаю Metallica")

    async def test_without_keys_opens_search(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(media, "wikidata", AsyncMock(return_value=None)):
            r = await tools.run("play_music", {"query": "linkin park", "kind": "artist"})
        self.launch.assert_awaited_with("xdg-open", "spotify:search:linkin park")
        self.assertTrue(r.ok)
        self.assertIn("ключ", r.say)

    async def test_starts_spotify_if_not_running(self):
        self.players = ""
        search = AsyncMock(return_value={"uri": "spotify:track:42", "name": "Numb", "by": "Linkin Park"})
        with patch.dict(os.environ, KEYS), patch.object(media, "search", search):
            r = await tools.run("play_music", {"query": "numb"})
        self.launch.assert_any_await("gtk-launch", "spotify")
        self.assertFalse(r.ok)                         # так и не появился за время ожидания
        self.assertNotIn(("playerctl", "-p", "spotify", "open", "spotify:track:42"), self.calls)


SEARCH = {"search": [{"id": "Q1"}, {"id": "Q2"}, {"id": "Q3"}]}
ENTITIES = {"entities": {
    "Q1": {"labels": {"ru": {"value": "Numb (альбом)"}}, "claims": {"P2205": [{"mainsnak": {"datavalue": {"value": "alb1"}}}]}},
    "Q2": {"labels": {"en": {"value": "Numb"}}, "claims": {"P2207": [{"mainsnak": {"datavalue": {"value": "trk2"}}}]}},
    "Q3": {"labels": {"ru": {"value": "Numb (группа)"}}, "claims": {"P1902": [{"mainsnak": {"datavalue": {"value": "art3"}}}]}}}}


class WikidataTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        import tempfile
        from pathlib import Path
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.get = AsyncMock(side_effect=lambda params: SEARCH if params["action"] == "wbsearchentities" else ENTITIES)
        for p in (patch.object(media, "_wd_get", self.get), patch.object(media, "CACHE", Path(tmp.name) / "c.json")):
            p.start()
            self.addCleanup(p.stop)

    async def test_prefers_requested_kind(self):
        self.assertEqual(await media.wikidata("Numb", "track"), {"uri": "spotify:track:trk2", "name": "Numb", "by": ""})
        self.assertEqual((await media.wikidata("Numb", "album"))["uri"], "spotify:album:alb1")

    async def test_any_prefers_artist(self):
        self.assertEqual((await media.wikidata("Numb", "any"))["uri"], "spotify:artist:art3")

    async def test_cached(self):
        await media.wikidata("Numb", "track")
        calls = self.get.await_count
        await media.wikidata("numb", "track")
        self.assertEqual(self.get.await_count, calls)

    async def test_network_error_is_none(self):
        self.get.side_effect = RuntimeError("429 Too Many Requests")
        self.assertIsNone(await media.wikidata("Metallica", "artist"))


class TokenTest(unittest.IsolatedAsyncioTestCase):
    async def test_token_cached_until_expiry(self):
        post = AsyncMock(return_value={"access_token": "t1", "expires_in": 3600})
        with patch.dict(os.environ, KEYS), patch.object(media, "_post_token", post):
            media._tok = None
            self.assertEqual(await media.token(), "t1")
            self.assertEqual(await media.token(), "t1")
        post.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
