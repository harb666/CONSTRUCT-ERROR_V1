"""Cuts the owner's robot boss walking sound into three single footstep
stomps, each starting right at its impact, so the game can play one exactly
when a foot lands:

    python3 tools/cut_boss_steps.py

Source (the owner's file, never changed): assets/audio/enemies/mini_boss_walking.mp3
(three heavy stomps ~1 s apart, each followed by its servo whine).
Out: assets/audio/enemies/mini_boss_step_1.ogg / _2 / _3 - mono, from 10 ms
before each stomp's impact onset (measured: 0.0814 / 1.0929 / 2.0860 s),
STEP_LEN s long with the last FADE s faded out.
"""
import os
import subprocess

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/audio/enemies/mini_boss_walking.mp3")
OUT = os.path.join(ROOT, "assets/audio/enemies/mini_boss_step_%d.ogg")
ONSETS = [0.0814, 1.0929, 2.0860]
PRE = 0.01
STEP_LEN = 0.9
FADE = 0.2

for i, onset in enumerate(ONSETS):
    start = onset - PRE
    length = min(STEP_LEN, 2.77 - start)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", "%.4f" % start, "-t", "%.4f" % length,
        "-i", SRC, "-ac", "1", "-ar", "44100",
        "-af", "afade=t=in:st=0:d=0.003,afade=t=out:st=%.3f:d=%.3f" % (length - FADE, FADE),
        "-c:a", "libvorbis", "-q:a", "7", OUT % (i + 1)], check=True)
    print(OUT % (i + 1), "from %.3f s, %.2f s" % (start, length))
