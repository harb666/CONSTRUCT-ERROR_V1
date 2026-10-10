"""Bakes the owner's Purple_Portal.mp4 (+ Portal_Matte.mp4) into the black
hole portal atlas used by BlackHolePortal.

  python3 tools/bake_portal.py

Source (owner's, untouched): assets/vfx/black_hole_portal/source/.
Output: assets/vfx/black_hole_portal/portal_atlas.png - 8 x 8 cells of
128 px, grey + alpha (2 bytes / pixel on the GPU):
  grey  = the portal's brightness (its colour comes back from ramp.png),
  alpha = the matte (the dark void) or the glow, whichever is stronger;
cells 0-43: steady loop (source frames 60.. every 2nd, the last 8 cross-
faded into the frames before the loop start, so it repeats seamlessly);
cells 44-53: opening, cells 54-63: closing, each picked at evenly spaced
ring sizes. portal_ramp.png: brightness -> colour, measured from the video.
portal_cells.json: each opening / closing cell's ring size (fraction of the
open ring), copied into black_hole_portal.gd.
"""
import json, os, subprocess, tempfile
import numpy as np
from PIL import Image

SRC = "assets/vfx/black_hole_portal/source"
OUT = "assets/vfx/black_hole_portal"
CX, CY, HALF = 318, 168, 128   # portal centre in the video, crop half-size
CELL, GRID = 128, 8
LOOP, LOOP_START, LOOP_STEP, FADE = 44, 60, 2, 8
OPEN_CELLS = CLOSE_CELLS = 10


def frames(name):
    d = tempfile.mkdtemp()
    subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(SRC, name), os.path.join(d, "%03d.png")], check=True)
    fs = sorted(os.listdir(d))
    return [np.asarray(Image.open(os.path.join(d, f)).convert("RGB")).astype(np.float32) / 255.0 for f in fs]


col = frames("Purple_Portal.mp4")
mat = frames("Portal_Matte.mp4")
n = len(col)


def crop(a):
    return a[CY - HALF:CY + HALF, CX - HALF:CX + HALF]


def radius(i):
    return float(np.sqrt((mat[i][..., 0] > 0.5).sum() / np.pi))


R_OPEN = np.median([radius(i) for i in range(60, 160)])


def cell(i):
    c = crop(col[i])
    m = crop(mat[i])[..., 0]
    lum = c @ np.array([0.3, 0.45, 0.25], np.float32)
    # Glow outside the matte; the video's dark noise floor is cut away.
    a = np.maximum(m, np.clip((c.max(axis=2) - 0.06) * 1.8, 0.0, 1.0))
    la = np.stack([lum, a], axis=2)
    img = Image.fromarray((la * 255).astype(np.uint8), "LA")
    return np.asarray(img.resize((CELL, CELL), Image.LANCZOS)).astype(np.float32)


cells = []
for k in range(LOOP):
    i = LOOP_START + k * LOOP_STEP
    c = cell(i)
    j = k - (LOOP - FADE)
    if j >= 0:  # cross-fade into the frames leading up to the loop start
        w = (j + 1) / (FADE + 1)
        c = c * (1 - w) + cell(LOOP_START - (FADE - j) * LOOP_STEP) * w
    cells.append(c)

info = {"open": [], "close": []}
open_r = [(i, radius(i) / R_OPEN) for i in range(0, 40)]
close_r = [(i, radius(i) / R_OPEN) for i in range(160, n)]
for key, seq, count in (("open", open_r, OPEN_CELLS), ("close", close_r, CLOSE_CELLS)):
    for k in range(count):
        want = (k + 1) / count  # 0.1 .. 1.0
        i, f = min(seq, key=lambda p: abs(p[1] - want))
        cells.append(cell(i))
        info[key].append(round(min(f, 1.0), 3))

atlas = np.zeros((CELL * GRID, CELL * GRID, 2), np.float32)
for k, c in enumerate(cells):
    x, y = k % GRID, k // GRID
    atlas[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = c
Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8), "LA").save(os.path.join(OUT, "portal_atlas.png"), optimize=True)

# Brightness -> colour ramp (average colour of the video's pixels per level).
acc = np.zeros((256, 3)); cnt = np.zeros(256)
for i in range(60, 160, 5):
    c = crop(col[i]).reshape(-1, 3)
    l = np.clip(c @ np.array([0.3, 0.45, 0.25]) * 255, 0, 255).astype(int)
    np.add.at(acc, l, c); np.add.at(cnt, l, 1)
ramp = np.zeros((256, 3)); last = np.zeros(3)
for l in range(256):
    if cnt[l] > 20:
        last = acc[l] / cnt[l]
    ramp[l] = last
Image.fromarray((ramp[None] * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "portal_ramp.png"))
info["matte_fraction"] = round(R_OPEN / HALF, 3)  # open ring radius / cell half-size
json.dump(info, open(os.path.join(OUT, "portal_cells.json"), "w"), indent=1)
print(info)
