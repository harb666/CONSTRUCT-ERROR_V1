#!/usr/bin/env python3
"""Bake Skyforge Arena's sky lighting the way the image-to-level preview
(three.js) lights its levels: the sunset panorama is the scene's environment
map (PMREM), so every surface is lit and reflects it according to its
roughness. This bakes that environment, pre-blurred with the GGX lobe for
roughness 0.25 / 0.5 / 0.75 / 1.0 (1.0 = the diffuse lighting, as three.js's
getIBLIrradiance uses), into one atlas: four 128 x 64 equirect bands stacked
top to bottom, same layout / orientation as the panorama (three.js equirectUv:
u = atan2(z, x) / 2pi + 0.5, v up). Stored sRGB-encoded (8-bit).

    python3 tools/bake_skyforge_ibl.py levels/skyforge_arena/sky/panorama.jpg \
        levels/skyforge_arena/sky/ibl_atlas.png
"""
import sys
import numpy as np
from PIL import Image

ROUGH = [0.25, 0.5, 0.75, 1.0]
OUT_W, OUT_H = 128, 64
SRC_W, SRC_H = 256, 128


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def dirs(w, h):
    """Unit directions of an equirect image's texel centres (row 0 = top)."""
    u = (np.arange(w) + 0.5) / w
    v = 1.0 - (np.arange(h) + 0.5) / h
    phi = (u - 0.5) * 2 * np.pi
    theta = (v - 0.5) * np.pi
    th, ph = np.meshgrid(theta, phi, indexing="ij")
    d = np.stack([np.cos(th) * np.cos(ph), np.sin(th), np.cos(th) * np.sin(ph)], -1)
    return d.reshape(-1, 3), np.cos(th).reshape(-1)


def main():
    src, out = sys.argv[1], sys.argv[2]
    im = Image.open(src).convert("RGB").resize((SRC_W, SRC_H), Image.LANCZOS)
    rad = srgb_to_lin(np.asarray(im, dtype=np.float64) / 255.0).reshape(-1, 3)
    ld, cos_lat = dirs(SRC_W, SRC_H)
    solid = cos_lat  # texel solid angle ~ cos(latitude)
    od, _ = dirs(OUT_W, OUT_H)
    bands = []
    for r in ROUGH:
        a2 = (r * r) ** 2
        res = np.zeros((od.shape[0], 3))
        for s in range(0, od.shape[0], 512):
            R = od[s:s + 512]
            rl = R @ ld.T  # cos between reflection dir and light dir
            ndl = np.clip(rl, 0.0, 1.0)
            ndh2 = np.clip((1.0 + rl) * 0.5, 0.0, 1.0)  # N = V = R
            D = a2 / (np.pi * (ndh2 * (a2 - 1.0) + 1.0) ** 2)
            w = D * ndl * solid[None, :]
            w /= np.maximum(w.sum(1, keepdims=True), 1e-12)
            res[s:s + 512] = w @ rad
        bands.append(res.reshape(OUT_H, OUT_W, 3))
    atlas = np.concatenate(bands, 0)
    Image.fromarray((lin_to_srgb(atlas) * 255.0 + 0.5).astype(np.uint8)).save(out)
    print("wrote", out, atlas.shape)


if __name__ == "__main__":
    main()
