"""Synthesises the plasma weapons' firing sounds (no samples needed):

  assets/audio/plasma/cannon_shot.ogg   - the arm cannon (player + grunts):
      a sharp energy crack, a fast falling "pew" with a little FM shimmer,
      a short sub thump and a sizzle tail (~0.35 s).
  assets/audio/plasma/shotgun_blast.ogg - the five-barrel plasma shotgun:
      a heavy crack, a deep falling boom, a wide plasma roar and a metallic
      vent clank as the barrels cool (~1.0 s).

python3 tools/make_weapon_sfx.py   (numpy, scipy, ffmpeg)
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "plasma")
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def sweep(f0, f1, sec, curve=6.0):
    """Sine whose frequency falls exponentially from f0 to f1."""
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-curve * t / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def env(sec, attack, decay):
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def band(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def low(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def high(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def pad(x, n):
    return np.pad(x, (0, max(n - len(x), 0)))[:n]


def master(x, peak=0.89):
    x = x - np.mean(x)
    # Gentle saturation for punch, then normalise; short fade at the end.
    x = np.tanh(x * 1.6)
    x *= peak / np.max(np.abs(x))
    fade = int(0.01 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def cannon_shot():
    sec = 0.36
    n = int(SR * sec)
    # Crack: a 4 ms band-passed noise click.
    crack = pad(band(rng.standard_normal(int(0.004 * SR)), 2500, 9000) * 1.2, n)
    # Pew: falling tone with FM shimmer.
    t = t_axis(sec)
    mod = 1 + 0.25 * np.sin(2 * np.pi * 95 * t) * np.exp(-t / 0.08)
    f = 260 + (1900 - 260) * np.exp(-9.0 * t / sec)
    pew = np.sin(2 * np.pi * np.cumsum(f * mod) / SR)
    pew += 0.35 * np.sign(pew) * np.abs(pew) ** 3  # a bit of edge
    pew *= env(sec, 0.002, 0.075)
    # Thump: short sub hit.
    thump = sweep(140, 48, 0.14, 4.0) * env(0.14, 0.001, 0.04)
    # Sizzle: high band noise, decaying, a little crackle.
    sz = band(rng.standard_normal(n), 3000, 11000) * env(sec, 0.004, 0.09)
    sz *= 1 + 0.6 * (rng.random(n) > 0.985)
    x = crack * 0.9 + pew * 0.55 + pad(thump, n) * 0.85 + sz * 0.18
    return master(x)


def shotgun_blast():
    sec = 1.05
    n = int(SR * sec)
    t = t_axis(sec)
    crack = pad(band(rng.standard_normal(int(0.007 * SR)), 1800, 10000) * 1.4, n)
    boom = sweep(120, 34, 0.6, 3.5) * env(0.6, 0.002, 0.16)
    # Roar: wide noise, low-passed with a falling cutoff (filter in chunks).
    noise = rng.standard_normal(n)
    roar = np.zeros(n)
    hop = 512
    for i in range(0, n, hop):
        cut = 300 + 5200 * np.exp(-(i / SR) / 0.09)
        seg = low(noise[max(i - 2048, 0):i + hop], cut)[-min(hop, n - i):]
        roar[i:i + hop] = seg
    roar *= env(sec, 0.002, 0.14)
    # Plasma whine on top: two falling tones.
    whine = (sweep(2400, 380, sec, 7.0) + 0.6 * sweep(1700, 300, sec, 6.0)) * env(sec, 0.003, 0.09)
    # Vent clank: a short metallic ring at ~0.42 s.
    k_at = int(0.42 * SR)
    kt = t_axis(0.25)
    clank = (np.sin(2 * np.pi * 1180 * kt) + 0.7 * np.sin(2 * np.pi * 1740 * kt) + 0.4 * np.sin(2 * np.pi * 2630 * kt))
    clank = clank * np.exp(-kt / 0.035) + band(rng.standard_normal(len(kt)), 2000, 7000) * np.exp(-kt / 0.01) * 0.6
    clank_full = np.zeros(n)
    clank_full[k_at:k_at + len(kt)] = clank[: n - k_at]
    hiss = high(rng.standard_normal(n), 4000) * np.clip((t - 0.45) / 0.05, 0, 1) * np.exp(-(t - 0.45).clip(0) / 0.18)
    x = crack + pad(boom, n) * 1.1 + roar * 0.9 + whine * 0.22 + clank_full * 0.16 + hiss * 0.05
    return master(x)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "a.wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        dst = os.path.join(OUT, name)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ac", "1",
                        "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    print("wrote", dst, "%.2f s" % (len(x) / SR))


if __name__ == "__main__":
    write("cannon_shot.ogg", cannon_shot())
    write("shotgun_blast.ogg", shotgun_blast())
