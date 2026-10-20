"""Спектр голоса для света острова ассистента: доли в четырёх полосах — низ (основной тон), середина (гласные),
верх (согласные) и шипящие. По ним нити света на стыке колышутся каждая от своей полосы — видно, что
Остров слышит саму речь, а не просто громкость. Считается для микрофона (stt) и для её голоса (tts).
"""
import numpy as np

EDGES = (80, 300, 1000, 3000, 8000)          # Гц
# в речи верх и шипящие на порядок тише низа — выравниваем, иначе их нитей почти не видно
TILT = np.array([1.0, 1.0, 1.6, 2.6])


def bands(x, rate: int) -> list:
    """Доли полос (в сумме 1) куска звука x; тишина и слишком короткий кусок — поровну."""
    x = np.asarray(x, dtype=np.float64)
    if len(x) < 32:
        return [0.25] * 4
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freq = np.fft.rfftfreq(len(x), 1.0 / rate)
    amp = np.array([np.sqrt((spec[(freq >= lo) & (freq < hi)] ** 2).sum()) for lo, hi in zip(EDGES, EDGES[1:])]) * TILT
    total = amp.sum()
    if total <= 1e-6 * len(x):
        return [0.25] * 4
    return [round(float(v / total), 3) for v in amp]
