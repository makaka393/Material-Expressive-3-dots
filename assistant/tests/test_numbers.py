import unittest

from glass_assistant.numbers import spoken


class SpokenTest(unittest.TestCase):
    def test_integers(self):
        self.assertEqual(spoken("Будет 391."), "Будет триста девяносто один.")
        self.assertEqual(spoken("0"), "ноль")
        self.assertEqual(spoken("12 и 40"), "двенадцать и сорок")

    def test_thousands(self):
        self.assertEqual(spoken("1500"), "одна тысяча пятьсот")
        self.assertEqual(spoken("2026"), "две тысячи двадцать шесть")
        self.assertEqual(spoken("11000"), "одиннадцать тысяч")
        self.assertEqual(spoken("3000000"), "три миллиона")

    def test_percent_agrees(self):
        self.assertEqual(spoken("Громкость 30%"), "Громкость тридцать процентов")
        self.assertEqual(spoken("1%"), "один процент")
        self.assertEqual(spoken("22 %"), "двадцать два процента")
        self.assertEqual(spoken("11%"), "одиннадцать процентов")

    def test_negative_and_decimal(self):
        self.assertEqual(spoken("-5 градусов"), "минус пять градусов")
        self.assertEqual(spoken("3,5 или 2.25"), "три запятая пять или два запятая двадцать пять")

    def test_time(self):
        self.assertEqual(spoken("в 14:05"), "в четырнадцать ноль пять")
        self.assertEqual(spoken("в 7:30"), "в семь тридцать")

    def test_no_digits_untouched(self):
        self.assertEqual(spoken("Привет, как дела?"), "Привет, как дела?")

    def test_dash_between_words_is_not_minus(self):
        self.assertEqual(spoken("с 5-10"), "с пять-десять")



class SpeakableTest(unittest.TestCase):
    def test_speakable_reads_numbers(self):
        from glass_assistant.tts import speakable
        self.assertEqual(speakable("**Громкость** 30%"), "Громкость тридцать процентов")


if __name__ == "__main__":
    unittest.main()
