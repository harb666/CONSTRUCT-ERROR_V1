"""Character art for the character select cards and the HUD portrait, cut
from the owner's banners (assets/ui/characters/source/<id>_banner.png,
untouched, not imported):

    python3 tools/build_character_art.py

- <id>_banner.png: the art inside the banner's slanted frame only (the grey
  metal frame and the white name plate are left out - the game draws its own
  cyan frame and name plate around it), transparent outside the slant,
  1024 px wide.
- <id>_portrait.png: a square around the face (HUD corner ring, squad rows).

Lager's banner (lager_banner.png) is the bare art on black, slanted less
steeply than the cards: the card's slanted shape (same aspect and slant as
the others) is cut from inside it, full width from its top, without
stretching or shearing the art (CUT_FROM_ART).
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
FACES = {"grinch": (612, 34, 500), "harbinger": (545, 34, 500), "lager": (880, 110, 500)}
# Art-only banners: id -> (x0, y0, height) of the card's bounding box in
# the source (its width = height * the cards' aspect).
CUT_FROM_ART = {"lager": (10, 12, 613)}
WIDTH = 1024
PORTRAIT = 256


def build(cid):
    if cid in CUT_FROM_ART:
        return build_cut(cid)
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


def build_cut(cid):
    im = Image.open(os.path.join(SRC, cid + "_banner.png")).convert("RGB")
    x0, y0, hc = CUT_FROM_ART[cid]
    aspect = 1024.0 / 291.0
    # The cards' slant share, from the shared template above.
    slant = -SLOPE * (BOTTOM - TOP) / (int(np.ceil(RIGHT_B + SLOPE * TOP - INSET)) + 1 - int(LEFT_B + SLOPE * BOTTOM + LEFT_INSET))
    wc = hc * aspect
    sw = slant * wc
    a = np.asarray(im.crop((x0, y0, x0 + int(round(wc)), y0 + hc))).astype(np.float32)
    h, w, _ = a.shape
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    left = sw * (1.0 - y / h)
    right = w - sw * y / h
    alpha = np.clip(x - left + 0.5, 0, 1) * np.clip(right - x + 0.5, 0, 1)
    out = Image.fromarray(np.dstack([a, alpha * 255]).astype(np.uint8), "RGBA")
    out = out.resize((WIDTH, round(WIDTH / aspect)), Image.LANCZOS)
    out.save(os.path.join(OUT, cid + "_banner.png"))
    fx, fy, fs = FACES[cid]
    im.crop((fx, fy, fx + fs, fy + fs)).resize((PORTRAIT, PORTRAIT), Image.LANCZOS).save(os.path.join(OUT, cid + "_portrait.png"))
    print(cid, "banner", out.size, "slant", round(slant, 4))


if __name__ == "__main__":
    import sys
    for cid in (sys.argv[1:] or FACES):
        build(cid)
