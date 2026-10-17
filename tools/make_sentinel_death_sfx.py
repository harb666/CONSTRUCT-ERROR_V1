#!/usr/bin/env python3
"""Builds the Neon Sentinel's three death sounds from the owner's two uploads:

    python3 tools/make_sentinel_death_sfx.py        (needs numpy and ffmpeg)

  in:  assets/audio/enemies/source/electric_impact.mp3      (owner's, untouched)
       assets/audio/enemies/source/distorted_explosion.mp3  (owner's, untouched)
  out: assets/audio/enemies/sentinel_death_1.ogg / _2.ogg / _3.ogg

The owner asked for at least three, each "a mini explosion sound followed by
clear electric sounds that matches all the animation and lasts around the
same length of time". The death (RobotSentinel.die) goes: the eye bursts at
once (glass, flash, smoke puff), the wings and antennae snap off over the
first ~0.25 s, then lightning crackles out of the socket, dying away over
~3.2 s. So each sound is ~3.3 s:

  * a mini explosion on the burst - the explosion upload's first punch
    (0.08-0.9 s of its 10 s), its long rumbling tail faded out by ~0.8 s so
    it stays small;
  * the electric impact upload laid in from 0.1 s, on top of the blast's
    fade and clear of it, crackling hard at first and dying away with the
    lightning.

The three differ so no two deaths sound the same:
  1 - the blast as recorded, then the full electric crackle;
  2 - a punchier, higher blast (sped up 1.18x), then the electric in
      stuttering bursts (its crackle re-struck in pieces, a little higher
      each time), like arcs jumping;
  3 - a deeper, shorter blast (slowed 0.9x), then the electric gated into a
      flicker that speeds up as it dies (the lightning flickering out).
"""
import os, subprocess, sys
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/audio/enemies/source")
OUT = os.path.join(ROOT, "assets/audio/enemies")
SR = 44100


def load(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(SRC, name), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def resample(a, speed):
    """Played `speed` times faster (pitch up / shorter)."""
    n = int(len(a) / speed)
    x = np.arange(n) * speed
    return np.stack([np.interp(x, np.arange(len(a)), a[:, c]) for c in range(2)], 1).astype(np.float32)


def fade(a, start, end):
    """Fades out from `start` to `end` seconds (silent after)."""
    t = np.arange(len(a)) / SR
    g = np.clip((end - t) / max(end - start, 1e-3), 0.0, 1.0) ** 1.5
    return a * g[:, None]


def place(out, a, at, gain=1.0):
    i = int(at * SR)
    n = min(len(a), len(out) - i)
    if n > 0:
        out[i:i + n] += a[:n] * gain


def blast(expl, speed, end):
    b = expl[int(0.08 * SR):int(1.0 * SR)]
    b = resample(b, speed) if speed != 1.0 else b
    return fade(b, end * 0.45, end)


def finish(mix, length):
    mix = mix[:int(length * SR)]
    t = np.arange(len(mix)) / SR
    mix *= np.clip((length - t) / 0.25, 0.0, 1.0)[:, None]  # no click at the end
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)  # soft limit
    return mix / max(np.abs(mix).max(), 1e-6) * 0.92


def write(mix, name):
    path = os.path.join(OUT, name)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=mix.astype(np.float32).tobytes(), check=True)
    print("wrote", name, "%.2f s" % (len(mix) / SR))


def main():
    elec = load("electric_impact.mp3")
    expl = load("distorted_explosion.mp3")
    L = 3.3
    # 1: the blast as recorded, then the full electric crackle.
    m = np.zeros((int(L * SR) + SR, 2), np.float32)
    place(m, blast(expl, 1.0, 0.8), 0.0, 0.85)
    place(m, elec, 0.1, 1.0)
    write(finish(m, L), "sentinel_death_1.ogg")
    # 2: punchier, higher blast; the electric re-struck in bursts.
    m = np.zeros((int(L * SR) + SR, 2), np.float32)
    place(m, blast(expl, 1.18, 0.6), 0.0, 0.9)
    pieces = [(0.0, 0.55, 0.08, 1.0, 1.0), (0.3, 0.75, 0.58, 1.06, 0.9), (0.15, 0.6, 1.02, 1.1, 0.75),
              (0.55, 1.1, 1.42, 1.04, 0.6), (1.1, 2.6, 1.9, 1.0, 0.55)]
    for a, b, at, sp, g in pieces:
        seg = elec[int(a * SR):int(b * SR)]
        seg = resample(seg, sp) if sp != 1.0 else seg
        n = len(seg)
        env = np.minimum(1.0, np.minimum(np.arange(n) / (0.006 * SR), (n - np.arange(n)) / (0.04 * SR)))
        place(m, seg * env[:, None], at, g)
    write(finish(m, L), "sentinel_death_2.ogg")
    # 3: deeper, shorter blast; the electric flickering out, faster and faster.
    m = np.zeros((int(L * SR) + SR, 2), np.float32)
    place(m, blast(expl, 0.9, 0.7), 0.0, 0.85)
    e = resample(elec, 1.05)
    t = np.arange(len(e)) / SR
    rate = 9.0 + 14.0 * np.clip(t / 2.6, 0.0, 1.0)
    phase = np.cumsum(rate) / SR
    gate = np.where(t < 0.5, 1.0, 0.25 + 0.75 * (np.sin(phase * 2 * np.pi) > -0.2))
    k = np.ones(64) / 64
    gate = np.convolve(gate, k, mode="same")  # soft edges: no clicks
    place(m, e * gate[:, None], 0.12, 1.0)
    write(finish(m, L), "sentinel_death_3.ogg")


if __name__ == "__main__":
    main()
