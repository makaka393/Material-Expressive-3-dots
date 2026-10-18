import unittest

from glass_assistant.intents import match

# фраза → (инструмент, аргументы); частые и однозначные — без модели
CASES = {
    "Громче": ("volume", {"change": 10}), "сделай погромче, пожалуйста": ("volume", {"change": 10}),
    "Тише.": ("volume", {"change": -10}), "убавь звук": ("volume", {"change": -10}),
    "громко слишком": ("volume", {"change": -10}), "слишком громко": ("volume", {"change": -10}),
    "плохо слышно": ("volume", {"change": 10}), "слишком тихо": ("volume", {"change": 10}),
    "громкость на 30": ("volume", {"level": 30}), "громкость 70 процентов": ("volume", {"level": 70}),
    "выключи звук": ("volume", {"mute": True}), "включи звук": ("volume", {"mute": False}),
    "ярче": ("brightness", {"change": 10}), "сделай темнее": ("brightness", {"change": -10}),
    "яркость на максимум": ("brightness", {"level": 100}), "яркость 40": ("brightness", {"level": 40}),
    "пауза": ("media", {"action": "pause"}), "поставь на паузу": ("media", {"action": "pause"}),
    "выключи музыку": ("media", {"action": "pause"}), "продолжи музыку": ("media", {"action": "play"}),
    "включи музыку": ("media", {"action": "play"}), "Следующий трек.": ("media", {"action": "next"}),
    "скип": ("media", {"action": "next"}), "включи другую песню": ("media", {"action": "next"}),
    "предыдущий трек": ("media", {"action": "previous"}), "верни предыдущую песню": ("media", {"action": "previous"}),
    "какая погода": ("system_info", {"kind": "weather"}), "Какая сегодня погода?": ("system_info", {"kind": "weather"}),
    "сколько времени": ("system_info", {"kind": "time"}), "который час": ("system_info", {"kind": "time"}),
    "какое сегодня число": ("system_info", {"kind": "date"}), "что сейчас играет": ("system_info", {"kind": "now_playing"}),
    "что за песня": ("system_info", {"kind": "now_playing"}),
    "насколько загружен процессор": ("system_info", {"kind": "cpu"}), "загрузка видеокарты": ("system_info", {"kind": "gpu"}),
    "сколько заряда в наушниках": ("system_info", {"kind": "headphones"}),
    "выключи компьютер": ("power", {"action": "shutdown"}), "перезагрузи комп": ("power", {"action": "reboot"}),
    "усыпи компьютер": ("power", {"action": "suspend"}),
    "заблокируй экран": ("screen", {"action": "lock"}), "сделай скриншот": ("screen", {"action": "screenshot"}),
    "скриншот области": ("screen", {"action": "screenshot_region"}), "смени обои": ("screen", {"action": "wallpaper"}),
    "начни запись экрана": ("screen", {"action": "record"}), "останови запись": ("screen", {"action": "stop_record"}),
    "включи ночной режим": ("toggle", {"feature": "night_light", "on": True}),
    "выключи ночной режим": ("toggle", {"feature": "night_light", "on": False}),
    "включи режим не беспокоить": ("toggle", {"feature": "do_not_disturb", "on": True}),
    "отключи не беспокоить": ("toggle", {"feature": "do_not_disturb", "on": False}),
    "выключи вайфай": ("toggle", {"feature": "wifi", "on": False}), "включи блютуз": ("toggle", {"feature": "bluetooth", "on": True}),
    "открой телегу": ("app", {"action": "open", "name": "телегу"}), "запусти стим": ("app", {"action": "open", "name": "стим"}),
    "закрой дискорд": ("app", {"action": "close", "name": "дискорд"}),
    "закрой это окно": ("window", {"action": "close"}), "разверни окно на весь экран": ("window", {"action": "fullscreen"}),
    "следующая вкладка": ("browser_tab", {"action": "next"}), "закрой вкладку": ("browser_tab", {"action": "close"}),
    "открой новую вкладку": ("browser_tab", {"action": "new"}),
    "перейди на второй рабочий стол": ("workspace", {"number": 2}), "третий рабочий стол": ("workspace", {"number": 3}),
    "следующий рабочий стол": ("workspace", {"direction": "next"}),
    "останови таймер": ("timer", {"action": "stop"}),
}
# не трогать: вопросы, отрицания, сложное — это модели
NOT = ["как выключить компьютер в линуксе", "не выключай компьютер, я ещё работаю", "почему небо синее",
       "громче и следующий трек", "сделай яркость поменьше и включи ночник", "включи linkin park", "вруби металлику",
       "поставь таймер на 10 минут", "напомни через 20 минут выключить плиту", "открой", "привет", "тише едешь дальше будешь",
       "какая погода будет в москве завтра", "открой новую вкладку и найди котиков"]


class IntentsTest(unittest.TestCase):
    def test_matches(self):
        for text, want in CASES.items():
            self.assertEqual(match(text), want, text)

    def test_leaves_rest_to_model(self):
        for text in NOT:
            self.assertIsNone(match(text), text)


if __name__ == "__main__":
    unittest.main()
