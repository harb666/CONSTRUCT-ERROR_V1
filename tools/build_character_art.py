"""Character art for the character select cards and the HUD portrait, cut
from the owner's banners (assets/ui/characters/source/<id>_banner.png,
untouched, not imported):

    python3 tools/build_character_art.py

- <id>_banner.png: the art inside the banner's slanted frame only (the grey
  metal frame and the white name plate are left out - the game draws its own
  cyan frame and name plate around it), transparent outside the slant,
  1024 px wide.
- <id>_portrait.png: a square around the face (HUD corner ring, squad rows).
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/ui/characters/source")
OUT = os.path.join(ROOT, "assets/ui/characters")

# The banners share one template: the art's slanted edges are
# x = b + SLOPE * y (left / right), between rows TOP and BOTTOM.
SLOPE = -0.6668
LEFT_B, RIGHT_B = 520.0, 2000.0
TOP, BOTTOM = 30, 540
INSET = 6.0
# The left edge has a bevel highlight in the frame: cut a little further in.
LEFT_INSET = 16.0
# Face squares (x, y, size) in banner pixels.
FACES = {"grinch": (612, 34, 500), "harbinger": (545, 34, 500)}
WIDTH = 1024
PORTRAIT = 256


def build(cid):
    im = Image.open(os.path.join(SRC, cid + "_banner.png")).convert("RGB")
    a = np.asarray(im).astype(np.float32)
    h, w, _ = a.shape
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    left = LEFT_B + SLOPE * y + LEFT_INSET
    right = RIGHT_B + SLOPE * y - INSET
    # Anti-aliased slant edges, hard top / bottom.
    alpha = np.clip(x - left + 0.5, 0, 1) * np.clip(right - x + 0.5, 0, 1)
    alpha *= (y >= TOP) & (y <= BOTTOM)
    x0 = int(LEFT_B + SLOPE * BOTTOM + LEFT_INSET)
    x1 = int(np.ceil(RIGHT_B + SLOPE * TOP - INSET)) + 1
    rgba = np.dstack([a, alpha * 255]).astype(np.uint8)[TOP:BOTTOM + 1, x0:x1]
    out = Image.fromarray(rgba, "RGBA")
    out = out.resize((WIDTH, round(out.height * WIDTH / out.width)), Image.LANCZOS)
    out.save(os.path.join(OUT, cid + "_banner.png"))
    fx, fy, fs = FACES[cid]
    im.crop((fx, fy, fx + fs, fy + fs)).resize((PORTRAIT, PORTRAIT), Image.LANCZOS).save(os.path.join(OUT, cid + "_portrait.png"))
    print(cid, "banner", out.size, "slant (share of the width)", round(-SLOPE * (BOTTOM - TOP) / (x1 - x0), 4))


if __name__ == "__main__":
    for cid in FACES:
        build(cid)
