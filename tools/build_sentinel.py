#!/usr/bin/env python3
"""Builds the game-ready Neon Sentinel (the flying enemy) from the owner's upload:

    python3 tools/build_sentinel.py      (needs numpy, Pillow, meshoptimizer)

  in:  assets/enemies/sentinel/source/Neon_Sentinel.glb   (untouched; the
       folder is .gdignore'd, so it isn't imported or exported)
  out: assets/enemies/sentinel/sentinel.glb

The source is already rigged for the game: 48 rigid bones (every mesh moves
with exactly one), the flight clips (Hover, Fly_Forward, Steer_Left /
Right, Brake), Startled_See_Player, the wing-plate clips and
Death_Eye_Burst, with the eye's glass shards, plasma and electric arcs
ready on their own bones. All of that is kept as it is. What changes:

  * Geometry: 161k triangles, half of them the body shell (84k) - too heavy
    for the phone. The dense meshes are reduced with meshoptimizer
    (attribute-aware: UV seams and normals kept, vertices only collapse onto
    existing ones, so UVs, tangents and skin weights stay exact): the body
    shell to ~20k, each wing backing to ~3.5k, the intact eye bulb (a plain
    sphere) to ~1.3k, the arms / sockets / couplings / antenna joints to
    half. The glass shards, arcs and small details are left as modelled.
  * Wing backs: the backing shells' paint mapping is broken (a black sheet
    with a torn pink rim) and the lime panel over it has a torn, saw-tooth
    edge; the backings are drawn in the model's own graphite housing
    material instead (clean dark backs, like the wings' frames).
  * Neon: the two neon materials (the body's selective neon and the wing
    backings') glowed at 3.5x, which renders blown-out white. They now glow
    at NEON_STRENGTH, so the neon reads as lime.
  * Textures: the 2048 px paint and emission maps go to 1024 px and every
    map is stored as JPEG, like the other robots' (small download, small
    graphics memory on the phone). The tiny 128 px maps keep their PNGs.
"""
import ctypes, io, json, os, struct, sys
import numpy as np
import meshoptimizer as mo
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/enemies/sentinel/source/Neon_Sentinel.glb")
OUT = os.path.join(ROOT, "assets/enemies/sentinel/sentinel.glb")

# Mesh -> fraction of its triangles kept; other meshes over DENSE triangles
# keep DEFAULT_KEEP (the arms, sockets, couplings, antenna joints, wing
# plates). The glass shards, arcs and small details are left as modelled.
DENSE = 1200
DEFAULT_KEEP = 0.5
SIMPLIFY = {
    "Original_Body": 0.24,
    "Moving_Wing_Backing_2": 0.33,
    "Moving_Wing_Backing_3": 0.33,
    "Smooth_Intact_Plasma_Bulb": 0.25,
}
# The wing backings: their painted shell's texture mapping is broken (black
# with a torn pink rim) and the lime panel over it has a torn, saw-tooth
# edge; both are drawn in the model's own graphite housing material
# instead - clean glossy backs like the wings' dark frames.
REPAINT = {"Moving_Wing_Backing_2": "Graphite_Mechanical_Housing", "Moving_Wing_Backing_3": "Graphite_Mechanical_Housing"}
REPAINT_FROM = ("Original_Paint_With_Selective_Neon", "Wing_Backing_Tip_Matched_Neon")
NEON = ("Original_Paint_With_Selective_Neon", "Wing_Backing_Tip_Matched_Neon")
NEON_STRENGTH = 1.3
MAX_TEX = 1024

# The package's wrapper calls meshopt_simplifyWithAttributes without declaring
# its argument types (64-bit counts passed as ints crash it): declared here.
from meshoptimizer._loader import lib as _mo_lib
_P = ctypes.POINTER
_mo_lib.meshopt_simplifyWithAttributes.argtypes = [
    _P(ctypes.c_uint), _P(ctypes.c_uint), ctypes.c_size_t, _P(ctypes.c_float), ctypes.c_size_t, ctypes.c_size_t,
    _P(ctypes.c_float), ctypes.c_size_t, _P(ctypes.c_float), ctypes.c_size_t, _P(ctypes.c_ubyte),
    ctypes.c_size_t, ctypes.c_float, ctypes.c_uint, _P(ctypes.c_float)]
_mo_lib.meshopt_simplifyWithAttributes.restype = ctypes.c_size_t

COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
TYPE_OF = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", d[off:off + 4])[0]
    return js, d[off + 8:off + 8 + bl]


def accessor(js, b, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    dt = np.dtype(COMP[a["componentType"]])
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or n * dt.itemsize
    raw = np.frombuffer(b, np.uint8, (a["count"] - 1) * stride + n * dt.itemsize, off)
    idx = np.arange(a["count"])[:, None] * stride + np.arange(n * dt.itemsize)[None, :]
    return raw[idx].copy().view(dt).reshape(a["count"], n)


class Writer:
    def __init__(self):
        self.buf = bytearray()
        self.views = []
        self.accessors = []

    def view(self, data, target=None):
        while len(self.buf) % 4:
            self.buf.append(0)
        v = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.buf += data
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, arr, like=None, target=None):
        arr = np.ascontiguousarray(arr)
        ct = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125, np.dtype(np.uint16): 5123, np.dtype(np.uint8): 5121}[arr.dtype]
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ct,
             "count": int(arr.shape[0]), "type": TYPE_OF[arr.shape[1]]}
        if like and like.get("normalized"):
            a["normalized"] = True
        if like and "min" in like:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.accessors.append(a)
        return len(self.accessors) - 1


def write_glb(path, js, buf):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((4 - len(j) % 4) % 4)
    buf = bytearray(buf)
    while len(buf) % 4:
        buf.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(buf)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(buf), 0x004E4942) + bytes(buf))


def simplify(attrs, idx, keep):
    """Reduced [attributes, indices] of one primitive (vertices only collapse
    onto existing ones; unused vertices dropped)."""
    pos = attrs["POSITION"].astype(np.float32)
    extra = [attrs["NORMAL"].astype(np.float32) * 0.5]
    w = [0.5, 0.5, 0.5]
    if "TEXCOORD_0" in attrs:
        extra.append(attrs["TEXCOORD_0"].astype(np.float32))
        w += [1.0, 1.0]
    va = np.ascontiguousarray(np.hstack(extra), np.float32)
    flat = np.ascontiguousarray(idx.reshape(-1), np.uint32)
    dest = np.zeros(flat.size, np.uint32)
    target = int(flat.size * keep) // 3 * 3
    n = mo.simplify_with_attributes(dest, flat, pos, va, np.array(w, np.float32),
                                    target_index_count=target, target_error=0.02)
    out = dest[:n]
    used = np.unique(out)
    remap = np.full(pos.shape[0], -1, np.int64)
    remap[used] = np.arange(used.size)
    new_attrs = {k: v[used] for k, v in attrs.items()}
    return new_attrs, remap[out].astype(np.uint32).reshape(-1, 1)


def main():
    js, b = read_glb(SRC)
    w = Writer()
    done = {}

    def copy(i, data=None, target=None):
        if data is None and i in done:
            return done[i]
        a = js["accessors"][i]
        arr = accessor(js, b, i) if data is None else data
        k = w.acc(arr, a, target)
        if data is None:
            done[i] = k
        return k

    before = after = 0
    mat_index = {mt["name"]: i for i, mt in enumerate(js["materials"])}
    for m in js["meshes"]:
        for p in m["primitives"]:
            if m["name"] in REPAINT and js["materials"][p.get("material", 0)]["name"] in REPAINT_FROM:
                p["material"] = mat_index[REPAINT[m["name"]]]
            idx = accessor(js, b, p["indices"])
            before += idx.size // 3
            mesh_tris = sum(js["accessors"][q["indices"]]["count"] // 3 for q in m["primitives"])
            keep = SIMPLIFY.get(m["name"], DEFAULT_KEEP if mesh_tris > DENSE else 1.0)
            if keep < 1.0 and idx.size // 3 > 200 and "NORMAL" in p["attributes"]:
                attrs = {k: accessor(js, b, v) for k, v in p["attributes"].items()}
                n0 = idx.size // 3
                attrs, idx = simplify(attrs, idx, keep)
                print("  %s: %d -> %d" % (m["name"], n0, idx.size // 3))
                for k in list(p["attributes"]):
                    p["attributes"][k] = copy(p["attributes"][k], attrs[k], 34962)
                p["indices"] = w.acc(idx.astype(np.uint32), None, 34963)
            else:
                for k in list(p["attributes"]):
                    p["attributes"][k] = copy(p["attributes"][k], None, 34962)
                p["indices"] = copy(p["indices"], None, 34963)
            after += idx.size // 3
    for s in js.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = copy(s["inverseBindMatrices"])
    for an in js.get("animations", []):
        for sm in an["samplers"]:
            sm["input"] = copy(sm["input"])
            sm["output"] = copy(sm["output"])
    for mat in js["materials"]:
        if mat["name"] in NEON:
            mat.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": NEON_STRENGTH}
    for im in js.get("images", []):
        bv = js["bufferViews"][im["bufferView"]]
        data = b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        img = Image.open(io.BytesIO(data))
        if max(img.size) <= 128:
            im["bufferView"] = w.view(data)
            continue
        img = img.convert("RGB")
        if max(img.size) > MAX_TEX:
            img = img.resize((MAX_TEX, MAX_TEX), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=92)
        im["bufferView"] = w.view(out.getvalue())
        im["mimeType"] = "image/jpeg"
        im["name"] = im.get("name", "").replace("2048", str(MAX_TEX))
    js["accessors"] = w.accessors
    js["bufferViews"] = w.views
    js["buffers"] = [{"byteLength": len(w.buf)}]
    js["asset"]["generator"] = "Neon Sentinel - tools/build_sentinel.py"
    write_glb(OUT, js, w.buf)
    print("triangles %d -> %d, %s: %d KB" % (before, after, OUT, os.path.getsize(OUT) // 1024))


if __name__ == "__main__":
    main()
