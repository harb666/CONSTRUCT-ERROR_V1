"""Skyforge sky (owner asked): the map maker's panorama has a bright pink
patch behind the sun with hard straight edges, so the sky read as two
different colours. This keeps the bright pink only as a soft glow round the
sun, fading smoothly into the rest of the sky; clouds, sun, planet stripes
and the horizon are untouched.

    python3 tools/smooth_sky_glow.py  (reads sky/source/panorama_original.jpg,
                                       writes sky/panorama.jpg)
"""
import numpy as np
from PIL import Image
from scipy import ndimage

DIR = "levels/skyforge_arena/sky/"
SKY = np.array([170.0, 45.0, 113.0])      # the sky's own background colour
BRIGHT = np.array([249.0, 75.0, 151.0])   # the patch's background colour
SUN = (540.0, 420.0)                      # sun centre in the 2048 x 1024 image
GLOW = (380.0, 330.0)                     # glow radii (x, y), px
H_TOP, H_BOT = 452.0, 470.0               # the correction fades out into the horizon glow

a = np.asarray(Image.open(DIR + "source/panorama_original.jpg").convert("RGB")).astype(np.float64)
h, w, _ = a.shape
ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
# How much of each pixel is the patch's bright background.
d = BRIGHT - SKY
m = np.clip(((a - SKY) @ d) / (d @ d), 0.0, 1.0)
# Keep it near the sun (smooth radial falloff), drop it elsewhere.
r = np.sqrt(((xs - SUN[0]) / GLOW[0]) ** 2 + ((ys - SUN[1]) / GLOW[1]) ** 2)
t = np.clip((r - 0.25) / 0.75, 0.0, 1.0)
keep = 1.0 - t * t * (3.0 - 2.0 * t)
region = np.clip((H_BOT - ys) / (H_BOT - H_TOP), 0.0, 1.0) * (xs < 1100)
out = a - ((1.0 - keep) * m * region)[..., None] * d
# The patch's outline (its anti-aliased rim) leaves a faint line: smooth
# just a thin band along it.
blob = ndimage.binary_closing((m > 0.5) & (region > 0.99) & (keep < 0.999), np.ones((41, 41)))
blob = ndimage.binary_fill_holes(blob)
rim = ndimage.binary_dilation(blob, iterations=4) & ~ndimage.binary_erosion(blob, iterations=4)
rim &= ys < H_TOP
smooth = np.stack([ndimage.median_filter(out[..., c], size=9) for c in range(3)], axis=-1)
out[rim] = smooth[rim]
Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8)).save(DIR + "panorama.jpg", quality=95)
