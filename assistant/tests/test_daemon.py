import asyncio
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from glass_assistant import config
from glass_assistant.claude import MissingKey
from glass_assistant.daemon import Daemon
from glass_assistant.local import Reply


class FakeBrain:
    """Мозг понарошку: печатает текст, выполняет «действия», запоминает вопросы."""

    def __init__(self, text="ответ", actions=(), error=None):
        self.text, self.actions, self.error = text, list(actions), error
        self.asked = []

    async def answer(self, text, voice, on_delta, on_action):
        self.asked.append(text)
        if self.error:
            raise self.error
        for a in self.actions:
            await on_action(a)
        if self.text:
            await on_delta(self.text)
        return Reply(self.text, self.actions)

    def reset(self):
        pass


NEXT = {"name": "media", "args": {"action": "next"}, "ok": True, "show": "Следующий трек", "say": None}


class DaemonTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        cfg = {**config.DEFAULTS, "speak_voice": False, "speak_typed": False}
        for p in (patch("glass_assistant.config.load", return_value=cfg),
                  patch("glass_assistant.config.has_key", return_value=True)):
            p.start()
            self.addCleanup(p.stop)
        self.d = Daemon()
        self.d.local_brain = FakeBrain("локально")
        self.d.claude_brain = FakeBrain("от Claude")
        self.d.local = AsyncMock()
        self.events = []

        async def emit(ev, **kw):
            self.events.append((ev, kw))
        self.d.emit = emit

    def ev(self, name):
        return [kw for e, kw in self.events if e == name]

    async def test_plain_to_local(self):
        await self.d.ask("следующий трек")
        self.assertEqual(self.d.local_brain.asked, ["следующий трек"])
        self.assertEqual(self.ev("done")[-1]["backend"], "local")

    async def test_word_to_claude(self):
        await self.d.ask("морковка, что такое кварк")
        self.assertEqual(self.d.claude_brain.asked, ["что такое кварк"])
        self.assertEqual(self.d.local_brain.asked, [])
        self.assertEqual(self.ev("done")[-1]["backend"], "claude")

    async def test_route_event_before_answer(self):
        # оболочка открывает окно ответа Claude сразу, ещё пока он думает
        await self.d.ask("морковь, что такое кварк")
        names = [e for e, _ in self.events]
        self.assertEqual(self.ev("route"), [{"brain": "claude", "text": "что такое кварк"}])
        self.assertLess(names.index("route"), names.index("delta"))

    async def test_to_claude(self):
        await self.d.ask("что такое кварк", to="claude")
        self.assertEqual(self.d.claude_brain.asked, ["что такое кварк"])

    async def test_word_alone_escalates(self):
        await self.d.ask("как работает ядро")
        await self.d.ask("морковка")
        self.assertEqual(self.d.claude_brain.asked, ["как работает ядро"])

    async def test_word_alone_nothing_typed(self):
        await self.d.ask("морковка")
        self.assertEqual(self.ev("error"), [{"text": "Что спросить у Claude?"}])
        self.assertEqual(self.d.claude_brain.asked, [])

    async def test_claude_unavailable(self):
        self.d.claude_brain = FakeBrain(error=MissingKey())
        await self.d.ask("морковка, что такое кварк")
        self.assertEqual(self.d.local_brain.asked, ["что такое кварк"])
        self.assertTrue(self.ev("delta")[0]["text"].startswith("Claude недоступен"))
        self.assertEqual(self.ev("done")[-1]["backend"], "local")

    async def test_local_down_uses_claude(self):
        self.d.local_brain = FakeBrain(error=RuntimeError("Локальная модель не запустилась"))
        await self.d.ask("привет")
        self.assertEqual(self.d.claude_brain.asked, ["привет"])
        self.assertTrue(self.ev("delta")[0]["text"].startswith("Локальная модель не запустилась"))

    async def test_local_down_no_key(self):
        self.d.local_brain = FakeBrain(error=RuntimeError("Локальная модель не запустилась"))
        with patch("glass_assistant.config.has_key", return_value=False):
            await self.d.command({"cmd": "ask", "text": "привет"})
            await self.d.job
        self.assertEqual(self.ev("error"), [{"text": "Локальная модель не запустилась"}])
        self.assertEqual(self.d.claude_brain.asked, [])

    async def test_actions_in_done(self):
        self.d.local_brain = FakeBrain("", [NEXT])
        await self.d.ask("следующий трек")
        self.assertEqual(self.ev("action"), [{"name": "media", "args": {"action": "next"}, "ok": True, "show": "Следующий трек"}])
        done = self.ev("done")[-1]
        self.assertEqual(done["text"], "Следующий трек")
        self.assertEqual(len(done["actions"]), 1)

    async def test_listen_warms(self):
        self.d.whisper = AsyncMock()
        with patch("glass_assistant.daemon.record_utterance", AsyncMock(return_value=None)):
            await self.d.listen(config.load())
        self.d.local.warm.assert_called_once()

    async def test_wake_name_only_chimes_and_listens(self):
        started = []
        self.d.start = lambda coro: (started.append(coro.__qualname__), coro.close())
        with patch("glass_assistant.daemon.chime.play") as play:
            await self.d.on_wake("Вега.", config.load())
        play.assert_called_once_with("wake")
        self.assertEqual(started, ["Daemon.listen"])

    async def test_wake_with_command_asks(self):
        started = []
        self.d.start = lambda coro: (started.append(coro.__qualname__), coro.close())
        with patch("glass_assistant.daemon.chime.play") as play:
            await self.d.on_wake("Вега, следующий трек", config.load())
        play.assert_not_called()
        self.assertEqual(started, ["Daemon.ask"])

    async def test_not_wake_ignored(self):
        started = []
        self.d.start = lambda coro: (started.append(coro.__qualname__), coro.close())
        await self.d.on_wake("купи хлеба", config.load())
        self.assertEqual(started, [])
        self.assertEqual(self.ev("heard"), [])

    async def test_say_preview_overrides_voice(self):
        # «прослушать» в настройках — сразу новым голосом, не дожидаясь записи настроек в файл
        self.d.voice = AsyncMock()
        await self.d.command({"cmd": "say", "text": "Привет", "voice": "aidar", "tone": -0.5, "speed": 1.2, "height": 0})
        text, cfg = self.d.voice.say.await_args.args
        self.assertEqual((text, cfg["voice"], cfg["voice_tone"], cfg["voice_speed"], cfg["voice_height"]),
                         ("Привет", "aidar", -0.5, 1.2, 0))
        self.d.voice.stop.assert_not_called()

    async def test_preview_cuts_previous(self):
        # ползунок тянут — звучит последнее прослушивание, а не очередь из всех
        self.d.voice = AsyncMock()
        self.d.voice.stop = lambda: calls.append("stop")
        calls = []
        await self.d.command({"cmd": "say", "text": "Привет", "preview": True, "tone": 1})
        self.assertEqual(calls, ["stop"])
        self.d.voice.say.assert_awaited_once()

    async def test_warm_unload_commands(self):
        await self.d.command({"cmd": "warm"})
        await self.d.command({"cmd": "unload"})
        self.d.local.warm.assert_called_once()
        self.d.local.unload.assert_awaited_once()


class FakeVoice:
    def __init__(self):
        self.idle = asyncio.Event()
        self.idle.set()
        self.said = []

    async def ready(self, cfg):
        pass

    async def say(self, text, cfg):
        self.said.append(text)

    def stop(self):
        pass


class DialogTest(unittest.IsolatedAsyncioTestCase):
    """После голосового ответа — слушать ещё раз без слова-активатора («поддерживать диалог»)."""

    async def asyncSetUp(self):
        cfg = {**config.DEFAULTS, "speak_voice": True, "follow_up": True}
        for p in (patch("glass_assistant.config.load", return_value=cfg),
                  patch("glass_assistant.config.has_key", return_value=True),
                  patch("glass_assistant.daemon.chime.play")):
            p.start()
            self.addCleanup(p.stop)
        self.d = Daemon()
        self.d.local_brain = FakeBrain("локально")
        self.d.claude_brain = FakeBrain("от Claude")
        self.d.local = AsyncMock()
        self.d.voice = FakeVoice()
        self.d.whisper = AsyncMock()
        self.heard = []                         # что «скажет» пользователь в следующих репликах (None — тишина)

        async def record(mic, on_level, **kw):
            self.waits = kw.get("max_wait")
            self.tail = kw.get("tail")
            return None if not self.heard or self.heard[0] is None else b"audio"
        self.d.whisper.transcribe.side_effect = lambda cfg, audio: self.heard.pop(0)
        p = patch("glass_assistant.daemon.record_utterance", record)
        p.start()
        self.addCleanup(p.stop)

        async def emit(ev, **kw):
            pass
        self.d.emit = emit

    async def test_follow_up_after_voice_answer(self):
        self.heard = ["а завтра?", None]
        await self.d.ask("какая погода", voice=True)
        self.assertEqual(self.d.local_brain.asked, ["какая погода", "а завтра?"])
        self.assertEqual(self.waits, 6)

    async def test_listen_uses_pause_setting(self):
        self.heard = ["а завтра?", None]
        with patch("glass_assistant.config.load", return_value={**config.DEFAULTS, "speak_voice": True,
                                                                "follow_up": True, "pause": 2.0}):
            await self.d.ask("какая погода", voice=True)
        self.assertEqual(self.tail, 2.0)

    async def test_no_follow_up_for_typed(self):
        self.heard = ["а завтра?"]
        await self.d.ask("какая погода")
        self.assertEqual(self.d.local_brain.asked, ["какая погода"])

    async def test_end_phrase_stops(self):
        from glass_assistant import daemon
        self.heard = ["Хватит."]
        await self.d.ask("какая погода", voice=True)
        self.assertEqual(self.d.local_brain.asked, ["какая погода"])
        daemon.chime.play.assert_called_with("done")

    async def test_whisper_noise_ignored(self):
        self.heard = ["Продолжение следует...", None]
        await self.d.ask("какая погода", voice=True)
        self.assertEqual(self.d.local_brain.asked, ["какая погода"])

    async def test_depth_limited(self):
        self.heard = ["ещё"] * 20
        await self.d.ask("начнём", voice=True)
        self.assertEqual(len(self.d.local_brain.asked), 1 + 5)

    async def test_claude_dialog_continues_with_claude(self):
        self.heard = ["а подробнее?", None]
        await self.d.ask("морковь, что такое кварк", voice=True)
        self.assertEqual(self.d.claude_brain.asked, ["что такое кварк", "а подробнее?"])

    async def test_follow_up_off(self):
        self.heard = ["а завтра?"]
        with patch("glass_assistant.config.load", return_value={**config.DEFAULTS, "speak_voice": True, "follow_up": False}):
            await self.d.ask("какая погода", voice=True)
        self.assertEqual(self.d.local_brain.asked, ["какая погода"])


class PowerFlowTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        from glass_assistant.tools import power
        self.power = power
        power.PENDING = None
        cfg = {**config.DEFAULTS, "speak_voice": True, "follow_up": False}
        self.calls = []

        async def sh(*argv, timeout=5):
            self.calls.append(argv)
            return ""
        for p in (patch("glass_assistant.config.load", return_value=cfg), patch("glass_assistant.daemon.chime.play"),
                  patch("glass_assistant.tools.base.sh", sh)):
            p.start()
            self.addCleanup(p.stop)
        self.d = Daemon()
        self.d.local_brain = FakeBrain("ответ")
        self.d.claude_brain = FakeBrain("от Claude")
        self.d.local = AsyncMock()
        self.d.voice = FakeVoice()
        self.events = []

        async def emit(ev, **kw):
            self.events.append((ev, kw))
        self.d.emit = emit

    async def test_yes_goes_to_power_not_model(self):
        import time as t
        self.power.PENDING = ("shutdown", t.monotonic() + 20)
        await self.d.ask("да")
        self.assertEqual(self.d.local_brain.asked, [])
        self.assertIn(("systemctl", "poweroff"), self.calls)
        self.assertEqual([kw["text"] for e, kw in self.events if e == "done"], ["Выключаю"])
        # как у любого ответа: «думаю» → ответ → «свободен» — иначе клиент ждёт конца вечно
        self.assertIn(("state", "thinking"), [(e, kw.get("state")) for e, kw in self.events])

    async def test_question_by_voice_listens_for_answer(self):
        # «выключи компьютер» голосом → «Выключить? Скажи да» → слушаем ответ, даже если «разговор» выключен
        import time as t
        power = self.power

        class AskingBrain(FakeBrain):
            async def answer(self, text, voice, on_delta, on_action):
                power.PENDING = ("shutdown", t.monotonic() + 20)
                return await super().answer(text, voice, on_delta, on_action)
        self.d.local_brain = AskingBrain("Выключить компьютер? Скажи «да».")
        self.d.listen = AsyncMock()
        await self.d.ask("выключи компьютер", voice=True)
        self.d.listen.assert_awaited_once()

    async def test_announce_reminder(self):
        qs = AsyncMock(return_value="")
        with patch("glass_assistant.tools.base.qs", qs):
            await self.d.announce("позвонить маме", "reminder")
        qs.assert_awaited_once_with("island", "toast", "alarm", "Напоминание", "позвонить маме")
        self.assertEqual(self.d.voice.said, ["Напоминаю: позвонить маме"])


class ServeTest(unittest.IsolatedAsyncioTestCase):
    async def test_voice_preloaded_on_start(self):
        # модель голоса грузится при запуске службы, а не при первом ответе (1,5 с + разогрев)
        with tempfile.TemporaryDirectory() as tmp, patch("glass_assistant.config.SOCKET", Path(tmp) / "a.sock"), \
                patch("glass_assistant.config.load", return_value=dict(config.DEFAULTS, wake=False)):
            d = Daemon()
            d.local = AsyncMock()
            d.voice.ready = AsyncMock()
            serving = asyncio.create_task(d.serve())
            for _ in range(100):
                if d.voice.ready.await_count:
                    break
                await asyncio.sleep(0.02)
            d.stopping.set()
            await asyncio.wait_for(serving, 3)
        d.voice.ready.assert_awaited()

    async def test_stops_with_client_connected(self):
        # оболочка держит сокет открытым всегда; служба всё равно должна выйти по SIGTERM сразу,
        # а не висеть до SIGKILL от systemd через полторы минуты
        with tempfile.TemporaryDirectory() as tmp, patch("glass_assistant.config.SOCKET", Path(tmp) / "a.sock"), \
                patch("glass_assistant.config.load", return_value=dict(config.DEFAULTS, wake=False)):
            d = Daemon()
            d.local = AsyncMock()
            d.voice.ready = AsyncMock()
            serving = asyncio.create_task(d.serve())
            for _ in range(100):
                if (Path(tmp) / "a.sock").exists():
                    break
                await asyncio.sleep(0.02)
            reader, writer = await asyncio.open_unix_connection(str(Path(tmp) / "a.sock"))
            await reader.readline()                              # первое событие state — клиент принят
            d.stopping.set()
            await asyncio.wait_for(serving, 3)
            writer.close()


class CliTest(unittest.IsolatedAsyncioTestCase):
    async def test_fire_and_forget_command_not_lost(self):
        # `python -m glass_assistant unload` пишет команду и сразу уходит; служба первым делом шлёт ему
        # состояние, запись в закрытый сокет рвёт соединение — и непрочитанная команда терялась
        with tempfile.TemporaryDirectory() as tmp, patch("glass_assistant.config.SOCKET", Path(tmp) / "a.sock"), \
                patch("glass_assistant.config.load", return_value=dict(config.DEFAULTS, wake=False)):
            d = Daemon()
            d.local = AsyncMock()
            d.voice.ready = AsyncMock()
            serving = asyncio.create_task(d.serve())
            for _ in range(100):
                if (Path(tmp) / "a.sock").exists():
                    break
                await asyncio.sleep(0.02)
            from glass_assistant.__main__ import client
            await client({"cmd": "unload"}, False)
            for _ in range(50):
                if d.local.unload.await_count:
                    break
                await asyncio.sleep(0.02)
            d.stopping.set()
            await asyncio.wait_for(serving, 3)
        d.local.unload.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()


def speech(spec):
    """[(«loud»|«quiet», секунд)] → кадры по 30 мс, как в test_stt."""
    import numpy as np
    from glass_assistant.stt import FRAME, RATE
    rng = np.random.default_rng(1)
    for kind, sec in spec:
        for _ in range(int(sec * RATE / FRAME)):
            if kind == "loud":
                t = np.arange(FRAME) / RATE
                yield (np.sin(2 * np.pi * 220 * t) * 4000).astype(np.int16)
            else:
                yield (rng.normal(0, 60, FRAME)).astype(np.int16)


async def stream(spec):
    for f in speech(spec):
        yield f
        await asyncio.sleep(0)


class WakeListenTest(unittest.IsolatedAsyncioTestCase):
    """Имя ловится по короткой паузе (0,7 с), а не после «паузы в конце фразы»; вопрос дослушивается."""

    async def asyncSetUp(self):
        self.cfg = {**config.DEFAULTS, "wake": True, "pause": 2.0}
        for p in (patch("glass_assistant.config.load", return_value=self.cfg),
                  patch("glass_assistant.config.has_key", return_value=False)):
            p.start()
            self.addCleanup(p.stop)
        self.d = Daemon()
        self.d.local = AsyncMock()
        self.heard = []                                  # что «распознал» Whisper — по очереди
        self.lens = []

        async def transcribe(cfg, audio, prompt=None):
            self.lens.append(len(audio))
            return self.heard.pop(0) if self.heard else ""
        self.d.whisper.transcribe = transcribe
        self.started = []
        self.d.start = lambda coro: (self.started.append(coro.cr_frame.f_locals.get("text") or coro.__qualname__),
                                     coro.close())
        self.events = []

        async def emit(ev, **kw):
            self.events.append((ev, kw))
        self.d.emit = emit

    async def test_name_alone_chimes_fast(self):
        self.heard = ["Вега."]
        with patch("glass_assistant.daemon.chime.play") as play:
            await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 0.5), ("quiet", 1.0), ("quiet", 5)]))
        play.assert_called_once_with("wake")
        self.assertEqual(self.started, ["Daemon.listen"])
        self.assertLess(self.lens[0] / 16000, 1.6)          # кусочек кончился через 0,7 с тишины, не через 2

    async def test_name_with_question_waits_for_rest(self):
        # «Вега, поставь будильник» … секунда раздумья … «на семь» — одна просьба
        self.heard = ["Вега, поставь будильник", "на семь"]
        with patch("glass_assistant.daemon.chime.play"):
            await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 1.0), ("quiet", 1.2), ("loud", 0.6),
                                                       ("quiet", 3.0)]))
        self.assertEqual(self.started, ["поставь будильник на семь"])
        self.assertIn(("state", {"state": "listening", "wake": True, "key": False}), self.events)

    async def test_name_with_question_no_rest(self):
        self.heard = ["Вега, какая погода?"]
        await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 1.0), ("quiet", 3.0)]))
        self.assertEqual(self.started, ["какая погода?"])
        self.assertEqual(len(self.lens), 1)                  # продолжения не было — второй раз не распознаём

    async def test_other_speech_ignored_and_keeps_listening(self):
        self.heard = ["купи хлеба", "Вега, громче"]
        await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 0.8), ("quiet", 1.0), ("loud", 0.8),
                                                   ("quiet", 3.0)]))
        self.assertEqual(self.started, ["громче"])

    async def test_near_miss_logged(self):
        self.heard = ["Вера, громче"]
        with patch("builtins.print") as out:
            await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 0.8), ("quiet", 1.0)]))
        self.assertEqual(self.started, [])
        self.assertIn("Вера", " ".join(str(c) for c in out.call_args_list))

    async def test_stops_when_wake_off(self):
        self.cfg["wake"] = False
        await asyncio.wait_for(self.d.wake_listen(self.cfg, stream([("quiet", 30)])), 5)
        self.assertEqual(self.lens, [])

    async def test_barge_in_while_speaking(self):
        # говорит — а ей «Вега!»: замолчать и слушать; её же речь перед именем — не вопрос
        self.d.voice.idle.clear()
        stops = []
        self.d.voice.stop = lambda: (stops.append(1), self.d.voice.idle.set())
        self.heard = ["Сегодня будет солнечно, Вега!"]
        with patch("glass_assistant.daemon.chime.play") as play:
            await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 2.0), ("quiet", 3.0)]))
        self.assertTrue(stops)
        play.assert_called_once_with("wake")
        self.assertEqual(self.started, ["Daemon.listen"])

    async def test_barge_in_with_question(self):
        self.d.voice.idle.clear()
        self.d.voice.stop = lambda: self.d.voice.idle.set()
        self.heard = ["будет солнечно. Вега, какая погода в Москве?"]
        await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 1.5), ("quiet", 3.0)]))
        self.assertEqual(self.started, ["какая погода в Москве?"])

    async def test_own_name_from_speakers_ignored(self):
        # «Привет! Я Вега…» из колонок — это не зовут
        self.d.voice.idle.clear()
        self.d.voice.said.append((__import__("time").monotonic(), "Привет! Я Вега."))
        self.heard = ["Привет, я Вега."] * 5
        await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 3.0), ("quiet", 0.5)]))
        self.assertEqual(self.started, [])

    async def test_name_while_thinking_cancels_old_answer(self):
        self.d.job = asyncio.create_task(asyncio.sleep(30))
        self.heard = ["Вега, стоп"]
        await self.d.wake_listen(self.cfg, stream([("quiet", 0.5), ("loud", 0.8), ("quiet", 3.0)]))
        await asyncio.sleep(0)
        self.assertTrue(self.d.job.cancelled())
        self.assertEqual(self.started, ["стоп"])

