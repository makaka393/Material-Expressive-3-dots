"""Голос ассистента: Silero TTS (русский, на процессоре) и воспроизведение через PipeWire (pw-play).

Ответ озвучивается по предложениям: первое уже звучит, пока модель дописывает остальные, следующее
синтезируется, пока играет текущее (синтез и проигрывание — две задачи), и всё — в один pw-play, без
запуска проигрывателя перед каждой фразой. Модель грузится и разогревается при запуске службы.
"""
import asyncio
import collections
import os
import re
import time

from . import config
from .numbers import spoken

RATE = 48000
LINGER = 0.3          # с — ждём следующую фразу, прежде чем закрыть проигрыватель
LEAD = 0.12           # с — новый pw-play начинает звучать примерно через столько (запуск и буфер)


def _num(v, lo, hi, default):
    try:
        return max(lo, min(hi, float(v)))
    except (TypeError, ValueError):     # старые настройки: "high", "fast"
        return default


def voice_of(cfg):
    """(голос, тон, скорость, высота) из настроек — вкладка «Голос»."""
    return (config.voice_id(cfg), _num(cfg.get("voice_tone"), -1, 1, 0.0),
            _num(cfg.get("voice_speed"), 0.75, 1.35, 1.0), _num(cfg.get("voice_height"), -1, 1, 0.0))


def prosody(tone, speed, height):
    """Ползунки → высота (±%) и скорость (%) для Silero. Тон чуть двигает и их: мягкий голос — немного выше
    и неспешнее, твёрдый — ниже и быстрее; остальное — тембр (shape)."""
    pitch = (1 + 0.15 * height) * (1 - 0.04 * tone)
    rate = speed * (1 + 0.05 * tone)
    return round((pitch - 1) * 100), round(rate * 100)


def _biquad(kind, f0, gain_db, q=0.707):
    """Коэффициенты фильтра (RBJ Audio EQ Cookbook): полка снизу/сверху или колокол."""
    import numpy as np
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / RATE
    cw, sw = np.cos(w0), np.sin(w0)
    if kind == "peak":
        al = sw / (2 * q)
        b = [1 + al * a_, -2 * cw, 1 - al * a_]
        a = [1 + al / a_, -2 * cw, 1 - al / a_]
    else:
        sq = 2 * np.sqrt(a_) * sw / np.sqrt(2)          # наклон полки S = 1
        if kind == "low":
            b = [a_ * ((a_ + 1) - (a_ - 1) * cw + sq), 2 * a_ * ((a_ - 1) - (a_ + 1) * cw), a_ * ((a_ + 1) - (a_ - 1) * cw - sq)]
            a = [(a_ + 1) + (a_ - 1) * cw + sq, -2 * ((a_ - 1) + (a_ + 1) * cw), (a_ + 1) + (a_ - 1) * cw - sq]
        else:
            b = [a_ * ((a_ + 1) + (a_ - 1) * cw + sq), -2 * a_ * ((a_ - 1) + (a_ + 1) * cw), a_ * ((a_ + 1) + (a_ - 1) * cw - sq)]
            a = [(a_ + 1) - (a_ - 1) * cw + sq, 2 * ((a_ - 1) - (a_ + 1) * cw), (a_ + 1) - (a_ - 1) * cw - sq]
    return np.array(b) / a[0], np.array(a) / a[0]


def shape(x, tone):
    """Тембр по ползунку «тон». Мягче — тише верх (теплее, без шипящих) и чуть полнее низ; твёрже — больше
    присутствия (около 3 кГц), суше низ и сжатая динамика: тихие слоги ближе к громким, голос плотнее и
    увереннее. Громкость (RMS) прежняя — меняется характер, а не уровень."""
    import numpy as np
    from scipy.signal import lfilter
    t = _num(tone, -1, 1, 0.0)
    if abs(t) < 0.05 or len(x) < 1024:
        return x
    x = x.astype(np.float64)
    level = np.sqrt(np.mean(x * x)) or 1e-9
    y = lfilter(*_biquad("low", 220, -2.5 * t), x)
    if t < 0:
        y = lfilter(*_biquad("high", 3000, 6.0 * t), y)
    else:
        y = lfilter(*_biquad("peak", 2800, 4.5 * t, q=0.9), y)
        k = np.exp(-1 / (0.012 * RATE))                     # огибающая громкости, ~12 мс
        env = np.sqrt(np.maximum(lfilter([1 - k], [1, -k], y * y), 1e-12))
        thr = 0.3 * env.max()
        ratio = 1 + 2 * t                                   # до 3:1
        gain = np.where(env > thr, (thr * (env / thr) ** (1 / ratio)) / env, 1.0)
        y = y * lfilter([1 - k], [1, -k], gain)
    y *= level / (np.sqrt(np.mean(y * y)) or 1e-9)
    peak = np.abs(y).max()
    if peak > 0.97:
        y *= 0.97 / peak
    return y.astype(np.float32)


class Voice:
    def __init__(self, spawn=None):
        self.model = None
        self.spawn = spawn or self._spawn
        self.texts = asyncio.Queue()     # (поколение, текст, голос) — ждут синтеза
        self.pcms = asyncio.Queue()      # (поколение, звук) — ждут проигрывателя
        self.synthesizing = False
        self.proc = None                 # pw-play текущего ответа
        self.gen = 0                     # растёт при stop(): всё, что было в очередях, уже не нужно
        self.idle = asyncio.Event()
        self.idle.set()
        self.tasks = None
        self.said = collections.deque(maxlen=12)   # (время, текст): что звучало — эхо из колонок не перебивает
        self.idle_at = 0.0                         # когда замолчала
        self.piper = {}                            # модель → PiperVoice
        self.on_level = None                       # async (0…1, полосы): громкость и спектр речи, пока звучит, — свет острова
        self.play_end = 0.0                        # когда доиграет отданное pw-play (часы цикла событий)

    def _load(self, path):
        import torch
        torch.set_num_threads(max(1, (os.cpu_count() or 8) // 2))      # 8 потоков — на треть быстрее 4
        model = torch.package.PackageImporter(path).load_pickle("tts_models", "model")
        model.to(torch.device("cpu"))
        return model

    def _piper_voice(self, model):
        """Голос Piper — грузится при первом обращении (~2 с) и остаётся в памяти (~70 МБ)."""
        if model not in self.piper:
            from piper import PiperVoice
            self.piper[model] = PiperVoice.load(str(config.PIPER / f"{model}.onnx"))
        return self.piper[model]

    async def ready(self, cfg):
        if self.model is None:           # Silero нужен всегда: и свои голоса, и русские фразы английских
            self.model = await asyncio.to_thread(self._load, cfg["tts_model"])
            try:                         # первый синтез после загрузки в разы медленнее — сделать его сразу
                await asyncio.to_thread(self._synth, "Привет.", ("xenia", 0.0, 1.0, 0.0))
            except Exception as e:
                print("tts: разогрев:", e, flush=True)
        info = config.voice(cfg)
        if info.engine == "piper" and info.model not in self.piper:
            try:
                await asyncio.to_thread(self._synth, "Hi." if info.lang == "en" else "Привет.", voice_of(cfg))
            except Exception as e:
                print("tts: piper:", repr(e), flush=True)
        if self.tasks is None:
            self.tasks = [asyncio.create_task(self._synth_loop()), asyncio.create_task(self._play_loop())]

    async def _spawn(self):
        return await asyncio.create_subprocess_exec(
            "pw-play", "--raw", "--format", "f32", "--rate", str(RATE), "--channels", "1",
            "--media-role", "Assistant", "-", stdin=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)

    def _synth(self, text, voice):
        if config.VOICES[voice[0]].engine == "piper":
            return self._synth_piper(text, voice)
        speaker, tone, speed, height = voice
        pitch, rate = prosody(tone, speed, height)
        if (pitch, rate) == (0, 100):
            src = {"text": text}
        else:                            # высота и скорость — через SSML, в процентах: тот же голос, без артефактов
            safe = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            src = {"ssml_text": f'<speak><prosody pitch="{pitch:+d}%" rate="{rate}%">{safe}</prosody></speak>'}
        try:
            audio = self.model.apply_tts(**src, speaker=speaker, sample_rate=RATE, put_accent=True, put_yo=True,
                                         put_stress_homo=True, put_yo_homo=True)
        except TypeError:                # у разных версий моделей свой набор параметров
            audio = self.model.apply_tts(**src, speaker=speaker, sample_rate=RATE)
        return shape(audio.numpy().astype("float32"), tone).tobytes()

    def _synth_piper(self, text, voice):
        """Piper: скорость — длиной звуков, высота — проигрываем быстрее в p раз (выше на p), а длину заранее
        растянули на столько же; тон — тем же тембром, что у Silero."""
        import numpy as np
        from fractions import Fraction
        from piper import SynthesisConfig
        from scipy.signal import resample_poly
        vid, tone, speed, height = voice
        pv = self._piper_voice(config.VOICES[vid].model)
        pitch, rate = prosody(tone, speed, height)
        p, r = 1 + pitch / 100, rate / 100
        syn = SynthesisConfig(length_scale=(pv.config.length_scale or 1.0) * p / r)
        chunks = [c.audio_float_array for c in pv.synthesize(text, syn_config=syn)]
        if not chunks:
            raise ValueError("пусто")
        f = Fraction(RATE / (pv.config.sample_rate * p)).limit_denominator(400)
        audio = resample_poly(np.concatenate(chunks), f.numerator, f.denominator).astype(np.float32)
        audio *= 0.8 / max(float(np.abs(audio).max()), 1e-6)     # Piper тянет пики к 1,0 — громче Silero (~0,8)
        return shape(audio, tone).tobytes()

    async def say(self, text: str, cfg):
        """В очередь на озвучку (одно предложение или фраза). У английского голоса русская фраза (подтверждение
        инструмента: «Громкость 35%») звучит голосом Silero того же пола — английский её не прочтёт."""
        voice = voice_of(cfg)
        info = config.VOICES[voice[0]]
        if info.lang == "en" and len(CYR.findall(text)) > len(LAT.findall(text)):
            voice, info = ("xenia" if info.female else "aidar",) + voice[1:], config.VOICES["xenia"]
        text = speakable(text, info.engine, info.lang)
        if not text:
            return
        await self.ready(cfg)
        self.said.append((time.monotonic(), text))
        self.idle.clear()
        await self.texts.put((self.gen, text, voice))

    def _more(self):
        return not self.texts.empty() or self.synthesizing or not self.pcms.empty()

    async def _synth_loop(self):
        while True:
            gen, text, voice = await self.texts.get()
            self.synthesizing = True
            pcm = None
            if gen == self.gen:
                try:
                    pcm = await asyncio.to_thread(self._synth, text, voice)
                except Exception as e:   # кривой текст не должен ронять озвучку
                    print("tts:", repr(e), repr(text[:80]), flush=True)
            self.synthesizing = False
            if pcm is not None and gen == self.gen:
                await self.pcms.put((gen, pcm))
            else:
                self._maybe_idle()

    async def _play_loop(self):
        while True:
            gen, pcm = await self.pcms.get()
            proc = None
            while True:                  # один ответ — один pw-play
                if gen == self.gen:
                    lead = 0.0
                    if proc is None or proc is not self.proc:     # первый кусок или после stop()
                        proc = self.proc = await self.spawn()
                        lead = LEAD
                    try:
                        proc.stdin.write(pcm)
                        await proc.stdin.drain()
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    if self.on_level:
                        self._levels(pcm, gen, lead)
                try:                     # дальше ещё будет — ждём сколько надо; иначе чуть-чуть
                    gen, pcm = await asyncio.wait_for(self.pcms.get(), None if self._more() else LINGER)
                except asyncio.TimeoutError:
                    break
            if proc is not None and proc is self.proc:
                try:
                    proc.stdin.close()
                except (BrokenPipeError, ConnectionResetError):
                    pass
                await proc.wait()        # доиграть то, что уже в буфере
                if proc is self.proc:
                    self.proc = None
            self._maybe_idle()

    def _levels(self, pcm, gen, lead):
        """Громкость и спектр куска по 30 мс — в on_level в том темпе, в каком он будет звучать: pw-play играет
        куски подряд, так что начало этого — когда кончится прошлый (или через lead, если проигрыватель новый)."""
        import numpy as np
        from .spectrum import bands
        x = np.frombuffer(pcm, dtype=np.float32)
        step = RATE * 3 // 100
        n = len(x) // step
        if n == 0:
            return
        parts = x[:n * step].reshape(n, step).astype(np.float64)
        env = np.sqrt((parts ** 2).mean(axis=1))
        spec = [bands(p, RATE) for p in parts]
        now = asyncio.get_running_loop().time()
        start = max(now + lead, self.play_end)
        self.play_end = start + len(x) / RATE
        asyncio.create_task(self._emit_levels(env, spec, start, step / RATE, gen))

    async def _emit_levels(self, env, spec, start, dt, gen):
        loop = asyncio.get_running_loop()
        for i, v in enumerate(env):
            delay = start + i * dt - loop.time()
            if delay > 0:
                await asyncio.sleep(delay)
            if gen != self.gen:
                return
            try:
                await self.on_level(min(1.0, float(v) * 4.0), spec[i])
            except Exception:
                return

    def _maybe_idle(self):
        if not self._more() and self.proc is None:
            self.idle.set()
            self.idle_at = time.monotonic()

    def said_recently(self, check, within=15.0) -> bool:
        """Звучало ли за within секунд что-то, где check(текст) — правда (своё имя в своей же речи)."""
        now = time.monotonic()
        return any(now - t < within and check(text) for t, text in self.said)

    def stop(self):
        """Замолчать сразу и забыть очереди."""
        self.gen += 1
        self.play_end = 0.0
        for q in (self.texts, self.pcms):
            while not q.empty():
                q.get_nowait()
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
        self.proc = None
        self.idle.set()
        self.idle_at = time.monotonic()


SENT_END = re.compile(r"(?<=[.!?…])\s+|\n+")


FIRST_CUT = re.compile(r"[,;:](?=\s)|\s[—–](?=\s)")


class Sentences:
    """Режет поток текста на предложения для озвучки. Первую реплику — уже по запятой, если до неё
    набралось ≥ 20 знаков: звук пойдёт раньше, чем модель допишет длинное предложение."""

    def __init__(self):
        self.buf = ""
        self.first = True

    def feed(self, chunk: str):
        self.buf += chunk
        if self.first and not SENT_END.search(self.buf):
            m = next((m for m in FIRST_CUT.finditer(self.buf) if m.start() >= 20), None)
            if not m:
                return []
            head, self.buf, self.first = self.buf[:m.end()].strip(), self.buf[m.end():].lstrip(), False
            return [head]
        out, start, acc = [], 0, ""
        for m in SENT_END.finditer(self.buf):
            piece = self.buf[start:m.start()].strip()
            start = m.end()
            acc = f"{acc} {piece}".strip()
            if len(acc) >= 12:                   # «Да.» склеиваем со следующим — меньше пауз
                out.append(acc)
                acc = ""
                self.first = False
        rest = self.buf[start:]
        self.buf = f"{acc} {rest}" if acc else rest
        return out

    def flush(self):
        head, self.buf = self.buf.strip(), ""
        return [head] if head else []


# Silero говорит только по-русски: латиницу он молча выбрасывает, а фраза из одной латиницы («Linkin Park —
# Numb», превью «Hi! This is…») падала целиком, без звука. Частые слова — как их говорят, остальное — по буквам
LATIN_WORDS = {
    "spotify": "спотифай", "youtube": "ютуб", "google": "гугл", "claude": "клод", "opus": "опус", "sonnet": "сонет",
    "haiku": "хайку", "gemma": "гемма", "wi-fi": "вай-фай", "wifi": "вайфай", "bluetooth": "блютус",
    "telegram": "телеграм", "discord": "дискорд", "steam": "стим", "github": "гитхаб", "linux": "линукс",
    "arch": "арч", "hyprland": "хайпрленд", "firefox": "файрфокс", "chrome": "хром", "zen": "зен",
    "windows": "виндоус", "iphone": "айфон", "apple": "эпл", "android": "андроид", "glass": "гласс",
    "ok": "окей", "okay": "окей", "hi": "хай", "hello": "хэллоу", "the": "зе", "and": "энд", "of": "оф",
    "you": "ю", "my": "май", "love": "лав", "me": "ми", "is": "из", "it": "ит", "in": "ин", "on": "он",
    "night": "найт", "day": "дэй", "life": "лайф", "time": "тайм", "world": "ворлд", "heart": "харт",
    "ayanami": "аян+ами", "here": "хиэр", "her": "хёр",
}
LETTERS = {"a": "эй", "b": "би", "c": "си", "d": "ди", "e": "и", "f": "эф", "g": "джи", "h": "эйч", "i": "ай",
           "j": "джей", "k": "кей", "l": "эл", "m": "эм", "n": "эн", "o": "оу", "p": "пи", "q": "кью", "r": "ар",
           "s": "эс", "t": "ти", "u": "ю", "v": "ви", "w": "дабл-ю", "x": "экс", "y": "уай", "z": "зед"}
SOUNDS = [("sch", "ш"), ("tch", "ч"), ("sh", "ш"), ("ch", "ч"), ("th", "т"), ("ph", "ф"), ("ck", "к"), ("qu", "кв"),
          ("oo", "у"), ("ee", "и"), ("ea", "и"), ("ou", "ау"), ("ow", "оу"), ("ay", "эй"), ("ai", "эй"), ("ey", "эй"),
          ("kh", "х"), ("zh", "ж"), ("ts", "ц"), ("ya", "я"), ("yu", "ю"), ("yo", "ё"), ("ye", "е"), ("x", "кс"),
          ("j", "дж"), ("w", "в"), ("a", "а"), ("b", "б"), ("c", "к"), ("d", "д"), ("e", "е"), ("f", "ф"), ("g", "г"),
          ("h", "х"), ("i", "и"), ("k", "к"), ("l", "л"), ("m", "м"), ("n", "н"), ("o", "о"), ("p", "п"), ("q", "к"),
          ("r", "р"), ("s", "с"), ("t", "т"), ("u", "у"), ("v", "в"), ("y", "и"), ("z", "з")]
LATIN_RX = re.compile(r"[A-Za-z][A-Za-z'-]*")


def _latin(m) -> str:
    w = m.group(0)
    low = w.lower().replace("'", "")
    if low in LATIN_WORDS:
        return LATIN_WORDS[low]
    if w.isupper() and len(w) <= 4:                      # GPU, USB, RTX — по буквам
        return "-".join(LETTERS[c] for c in low if c in LETTERS)
    low = re.sub(r"(?<=[a-z])e$", "", low) or low        # немое e на конце: «love», «fade»
    out, i = "", 0
    while i < len(low):
        for lat, ru in SOUNDS:
            if low.startswith(lat, i):
                out, i = out + ru, i + len(lat)
                break
        else:
            out, i = out + low[i], i + 1
    return re.sub(r"(?<=[бвгджзклмнпрстфхцчшщ])и(?=[аоуэ])", "й", out)


CYR = re.compile(r"[А-Яа-яЁё]")
LAT = re.compile(r"[A-Za-z]")


def speakable(text: str, engine: str = "silero", lang: str = "ru") -> str:
    """Убрать то, что вслух не читают (разметку, ссылки, эмодзи). По-русски ещё латиницу — русскими буквами,
    а числа — словами: Silero цифры глотает; ему же ударение в имени: «Аян+ами» (Piper «+» не
    понимает). По-английски Piper сам читает и числа."""
    t = re.sub(r"https?://\S+", "", text)
    t = re.sub(r"`{1,3}[^`]*`{1,3}", "", t)
    t = re.sub(r"[*_#>|~^]+", "", t)
    t = re.sub(r"[\U0001F000-\U0001FFFF☀-➿]", "", t)
    t = t.replace("—", ", ").replace("–", ", ")
    if lang == "en":
        return " ".join(t.split()).strip()
    t = LATIN_RX.sub(_latin, t)
    if engine == "silero":
        t = re.sub(r"(?<![\w+])(А|а)ян(ами)(?!\w)", r"\1ян+\2", t)
    else:
        t = t.replace("+", "")
    return spoken(" ".join(t.split()).strip())
