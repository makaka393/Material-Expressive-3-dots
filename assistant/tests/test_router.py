import unittest

from glass_assistant import config
from glass_assistant.router import Route, route, strip_word

CFG = {"backend": "auto", "claude_words": ["морковка"]}


class RouteTest(unittest.TestCase):
    def test_plain_goes_local(self):
        self.assertEqual(route("следующий трек", CFG), Route("local", "следующий трек", False))

    def test_word_goes_claude(self):
        self.assertEqual(route("Морковка, почему небо синее?", CFG), Route("claude", "почему небо синее?", False))

    def test_word_forms(self):
        # падежи, знаки и огрехи распознавания
        for t in ("морковку, что такое кварк", "морковка! что такое кварк", "эй морковка что такое кварк"):
            self.assertEqual(route(t, CFG), Route("claude", "что такое кварк", False), t)

    def test_word_later_in_phrase_ignored(self):
        self.assertEqual(route("купи морковку и лук пожалуйста", CFG).brain, "local")

    def test_word_alone_escalates_last(self):
        self.assertEqual(route("морковка", CFG, last="как работает ядро"), Route("claude", "как работает ядро", True))

    def test_word_alone_no_last(self):
        self.assertEqual(route("Морковка.", CFG), Route("claude", "", True))

    def test_to_claude(self):
        self.assertEqual(route("привет", CFG, to="claude"), Route("claude", "привет", False))

    def test_backend_claude(self):
        self.assertEqual(route("привет", {**CFG, "backend": "claude"}).brain, "claude")

    def test_backend_local_ignores_word(self):
        self.assertEqual(route("морковка, привет", {**CFG, "backend": "local"}), Route("local", "морковка, привет", False))


class DefaultWordsTest(unittest.TestCase):
    """Слова по умолчанию: «Вега» — активатор, «морковь» — в Claude (любая форма)."""

    def test_morkov_forms(self):
        for t in ("морковь, почему небо синее", "Морковка, почему небо синее", "морковку почему небо синее"):
            self.assertEqual(route(t, config.DEFAULTS), Route("claude", "почему небо синее", False), t)

    def test_name_then_morkov(self):
        from glass_assistant.router import wake
        rest = wake("Вега, морковь, почему небо синее?", config.wake_words(config.DEFAULTS))
        self.assertEqual(route(rest, config.DEFAULTS), Route("claude", "почему небо синее?", False))

    def test_quotes_stripped(self):
        # Whisper иногда берёт фразу в «ёлочки»
        self.assertEqual(strip_word("«Обсидиан, морковь, почему?»", ["обсидиан"]), "морковь, почему?")

    def test_name_latin(self):
        # Whisper иногда пишет имя латиницей
        from glass_assistant.router import wake
        self.assertEqual(wake("Vega, выкрути яркость на максимум.", config.wake_words(config.DEFAULTS)),
                         "выкрути яркость на максимум.")

    def test_name_plain_is_local(self):
        from glass_assistant.router import wake
        rest = wake("Вега, выкрути яркость на максимум", config.wake_words(config.DEFAULTS))
        self.assertEqual(route(rest, config.DEFAULTS), Route("local", "выкрути яркость на максимум", False))


class StripWordTest(unittest.TestCase):
    def test_any_lead_by_default(self):
        # слово-активатор: «окей гласс …», «ну гласс …» — как раньше в after_wake
        self.assertEqual(strip_word("ну гласс, какая погода", ["гласс"]), "какая погода")

    def test_no_word(self):
        self.assertIsNone(strip_word("какая погода", ["гласс"]))


class NameTest(unittest.TestCase):
    """Имя ассистента — «Вега», оно же слово-активатор."""

    def test_name(self):
        self.assertEqual(config.NAME, "Вега")
        self.assertNotIn("name", config.DEFAULTS)

    def test_heard_forms(self):
        from glass_assistant.router import wake
        for heard, rest in [("Вега, громче", "громче"), ("Вега.", ""), ("Vega, громче", "громче"),
                            ("- Вега, какая погода?", "какая погода?"), ("«Вега, следующий трек»", "следующий трек"),
                            ("эй, Вега", ""), ("Так, Вега, громче.", "громче.")]:
            self.assertEqual(wake(heard, config.wake_words(config.DEFAULTS)), rest, heard)

    def test_name_at_end_takes_question_before(self):
        from glass_assistant.router import wake
        w = config.wake_words(config.DEFAULTS)
        self.assertEqual(wake("Какая погода, Вега?", w), "Какая погода")
        self.assertEqual(wake("Слушай, громче, Вега!", w), "громче")
        self.assertEqual(wake("Ну и дела. Вега.", w), "")              # другое предложение — только имя
        self.assertEqual(wake("Будет солнечно, Вега", w, before=False), "")   # перебили — её речь не вопрос

    def test_old_names_retired(self):
        from glass_assistant.router import wake
        for heard in ("Обсидиан, громче", "Ирис, громче", "Аврора, громче"):
            self.assertIsNone(wake(heard, config.wake_words({**config.DEFAULTS, "name": "Ирис"})), heard)

    def test_no_false_names(self):
        from glass_assistant.router import wake
        for heard in ("Лас-Вегас красивый", "вегетарианский суп", "его нет дома", "век живи", "Ева пришла"):
            self.assertIsNone(wake(heard, config.wake_words(config.DEFAULTS)), heard)

    def test_extra_wake_words_kept(self):
        cfg = {**config.DEFAULTS, "wake_words": ["джарвис"]}
        self.assertIn("джарвис", config.wake_words(cfg))

    def test_gender_from_voice(self):
        self.assertTrue(config.female({**config.DEFAULTS, "voice": "baya"}))
        self.assertFalse(config.female({**config.DEFAULTS, "voice": "aidar"}))


if __name__ == "__main__":
    unittest.main()


class WakeTest(unittest.TestCase):
    """«Обсидиан», «обс», «обси», «обсик» — и как их слышит Whisper (синтез Silero → Whisper, 2026-10-18)."""

    W = ["обсидиан", "обс", "обси", "обсик", "obsidian", "obs"]

    def test_heard_variants(self):
        from glass_assistant.router import wake
        for heard, rest in [("Обсидиан.", ""), ("обсидиан", ""), ("Обсидианчик, привет!", "привет!"),
                            ("Obsidian, выкрути яркость", "выкрути яркость"), ("Опс.", ""), ("Обс.", ""),
                            ("Обс, следующий трек.", "следующий трек."), ("Опс, следующий трек.", "следующий трек."),
                            ("Обси.", ""), ("Общи.", ""), ("Обсе.", ""), ("ОПСИ, открой телегу.", "открой телегу."),
                            ("а псих громче.", "громче."), ("А ПСИК громче.", "громче."), ("OBS, громче", "громче"),
                            ("эй, обси, громче", "громче"), ("«Обсидиан, морковь, почему?»", "морковь, почему?")]:
            self.assertEqual(wake(heard, self.W), rest, heard)

    def test_not_wake(self):
        from glass_assistant.router import wake
        for heard in ("обсудим планы на завтра", "обслуживание закончилось", "обстановка нормальная", "а потом домой",
                      "псих какой-то", "купи хлеба", "", "Продолжение следует..."):
            self.assertIsNone(wake(heard, self.W), heard)
