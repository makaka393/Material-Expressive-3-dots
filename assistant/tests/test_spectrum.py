"""Спектр голоса для света острова: доли в четырёх полосах — нити света колышутся каждая от своей."""
import unittest

import numpy as np

from glass_assistant.spectrum import bands


def tone(hz, rate=16000, n=480):
    return np.sin(2 * np.pi * hz * np.arange(n) / rate) * 3000


class BandsTest(unittest.IsolatedAsyncioTestCase):
    def test_each_band_hears_its_tone(self):
        for hz, band in ((150, 0), (600, 1), (2000, 2), (5000, 3)):
            b = bands(tone(hz), 16000)
            self.assertEqual(int(np.argmax(b)), band, (hz, b))

    def test_shares_sum_to_one(self):
        b = bands(tone(150) + tone(2000), 16000)
        self.assertAlmostEqual(sum(b), 1.0, places=2)
        self.assertEqual(len(b), 4)

    def test_silence_and_short_are_even(self):
        self.assertEqual(bands(np.zeros(480), 16000), [0.25] * 4)
        self.assertEqual(bands(np.ones(8), 16000), [0.25] * 4)

    def test_other_rate(self):
        # голос Веги — 48 кГц, куски по 30 мс
        self.assertEqual(int(np.argmax(bands(tone(5000, 48000, 1440), 48000))), 3)
