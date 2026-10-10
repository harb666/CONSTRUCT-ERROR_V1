"""Builds the playable Harbinger model from the owner's upload.

    python3 tools/build_harbinger.py
    (then gltfpack + transplant, see build() - needs gltfpack on PATH or GLTFPACK)

Source: assets/characters/harbinger/source/harbinger_source.glb (untouched, not
imported or exported: .gdignore). Output: assets/characters/harbinger/harbinger.glb.

1. Arm ends: the forearms end in a built-in blaster (black barrel + lens,
   the "hands"). Like the Grinch's open gauntlets, they are cut off where the
   blue gauntlet ends (a plane across the forearm axis; triangles crossing it
   are clipped exactly, so the rim is clean), leaving an opening the arm
   weapons plug into. tools/build_mesh_caps.gd then seals the openings.
2. Feet: the clips (same library as the Grinch's) were retargeted with the
   feet pitched toes-up by ~20 deg against this model's flat boot soles, so
   standing she only touched the ground with her heels. A constant local
   correction on each Foot bone (the smallest tilt that makes the idle's
   soles level; no twist) is applied to every key of every clip.
2b. The painted halo ring above her head is removed; the game draws a
   glowing electric ring there instead (scripts/character/halo_ring.gd).
3. Clips get the Grinch's names (the CharacterAnimator uses them):
   Idle_9 -> "Idle 9", Fall_Dead_from_Abdominal_Injury -> "Dead",
   Jump_Over_Obstacle_2 -> "Climb Attempt and Fall 5" (unused) ... She has no
   mid-air falling loop ("Fall2"); one is made from her own Regular Jump's
   descending frames (played forward then back). Unused clips are dropped.
4. Meshes simplified with gltfpack (-si 0.6, border locked, names/materials/
   skin kept) and the step-1..3 animation data copied back byte for byte
   (tools/transplant_animations.py), as for the Grinch.
"""
import json, os, struct, subprocess, sys
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/characters/harbinger/source/harbinger_source.glb")
OUT = os.path.join(ROOT, "assets/characters/harbinger/harbinger.glb")

# Distance (m) from the forearm joint along the forearm axis where the blue
# gauntlet ends and the blaster begins (measured from the texture colours).
CUT = {"Left": 0.370, "Right": 0.398}
RENAME = {
    "Idle_9": "Idle 9", "Idle_Turn_Left": "Idle Turn Left", "Idle_Turn_Right": "Idle Turn Right",
    "Regular_Jump": "Regular Jump", "Run_Sharp_Turn_Right": "Run Sharp Turn Right",
    "slide_right": "slide right", "Fall_Dead_from_Abdominal_Injury": "Dead",
    "Jump_Over_Obstacle_2": "Climb Attempt and Fall 5",
    "Fall1": "Fall1", "Running": "Running", "Walking": "Walking", "RunFast": "RunFast",
}
# Fall2: Regular Jump's descent, forward then back, over FALL2_LEN s.
FALL2_FROM, FALL2_TO, FALL2_LEN = 0.80, 0.95, 0.7


# --- GLB io ---------------------------------------------------------------

def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", d[off:off + 4])[0]
    return js, d[off + 8:off + 8 + bl]


COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def accessor(js, b, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    dt = np.dtype(COMP[a["componentType"]])
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or n * dt.itemsize
    raw = np.frombuffer(b, np.uint8, (a["count"] - 1) * stride + n * dt.itemsize, off)
    idx = np.arange(a["count"])[:, None] * stride + np.arange(n * dt.itemsize)[None, :]
    out = raw[idx].copy().view(dt).reshape(a["count"], n)
    if a.get("normalized") and dt.kind == "u":
        out = out.astype(np.float32) / np.iinfo(dt).max
    return out


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

    def acc(self, arr, typ, minmax=False, target=None):
        arr = np.ascontiguousarray(arr)
        ct = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125, np.dtype(np.uint16): 5123, np.dtype(np.uint8): 5121}[arr.dtype]
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ct,
             "count": int(arr.shape[0]), "type": typ}
        if minmax:
            flat = arr.reshape(arr.shape[0], -1)
            a["min"] = [float(x) for x in flat.min(0)]
            a["max"] = [float(x) for x in flat.max(0)]
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


# --- maths ----------------------------------------------------------------

def qmul(a, b):
    x1, y1, z1, w1 = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    x2, y2, z2, w2 = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], -1)


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_q(m):
    from scipy.spatial.transform import Rotation
    return Rotation.from_matrix(m).as_quat()


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def sample(tin, out, t, rot):
    k = int(np.searchsorted(tin, t))
    if k <= 0:
        return out[0]
    if k >= len(tin):
        return out[-1]
    f = (t - tin[k - 1]) / (tin[k] - tin[k - 1])
    return slerp(out[k - 1], out[k], f) if rot else out[k - 1] * (1 - f) + out[k] * f


# --- rig ------------------------------------------------------------------

class Rig:
    """Node TRS + clip sampling + skinning (for measuring the feet)."""

    def __init__(self, js, anims):
        self.js = js
        self.anims = anims  # name -> {(node, path): (tin, out)}
        self.parent = {}
        for i, n in enumerate(js["nodes"]):
            for c in n.get("children", []):
                self.parent[c] = i

    def globals(self, clip, t, corr=None):
        js = self.js
        T, R = {}, {}
        for i, n in enumerate(js["nodes"]):
            T[i] = np.array(n.get("translation", [0, 0, 0]), float)
            R[i] = np.array(n.get("rotation", [0, 0, 0, 1]), float)
        if clip:
            for (node, path), (tin, out) in self.anims[clip].items():
                v = sample(tin, out, t, path == "rotation")
                (R if path == "rotation" else T)[node] = v
        for node, q in (corr or {}).items():
            R[node] = qmul(R[node], q)
        G = {}

        def g(i):
            if i not in G:
                M = np.eye(4)
                M[:3, :3] = qmat(R[i])
                M[:3, 3] = T[i]
                G[i] = g(self.parent[i]) @ M if i in self.parent else M
            return G[i]
        return {i: g(i) for i in range(len(js["nodes"]))}


def build_prep():
    js, b = read_glb(SRC)
    skin = js["skins"][0]
    joints = skin["joints"]
    names = {js["nodes"][k]["name"]: k for k in joints}
    ibm = accessor(js, b, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
    bind = {joints[i]: np.linalg.inv(ibm[i]) for i in range(len(joints))}
    prim = js["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    P = accessor(js, b, at["POSITION"]).astype(np.float64)
    N = accessor(js, b, at["NORMAL"]).astype(np.float64)
    UV = accessor(js, b, at["TEXCOORD_0"]).astype(np.float64)
    J = accessor(js, b, at["JOINTS_0"]).astype(np.int64)
    W = accessor(js, b, at["WEIGHTS_0"]).astype(np.float64)
    I = accessor(js, b, prim["indices"]).reshape(-1, 3).astype(np.int64)

    # 1. Arm ends.
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        fa = bind[names["mixamorig:%sForeArm" % side]][:3, 3]
        hd = bind[names["mixamorig:%sHand" % side]][:3, 3]
        ax = (hd - fa) / np.linalg.norm(hd - fa)
        d = (P - fa) @ ax - CUT[side]
        region = P[:, 0] * sx > 0.55
        P, N, UV, J, W, I, removed = clip_mesh(P, N, UV, J, W, I, d, region)
        print("%s arm end: cut %.3f m past the elbow, %d triangles removed/clipped" % (side, CUT[side], removed))
    # Halo: the model's painted halo (its own separate ring of geometry above
    # the head) is removed; the game draws a glowing electric ring in its
    # place (scripts/character/halo_ring.gd, fitted to these numbers).
    I = remove_halo(P, I)
    # Drop unused vertices.
    used = np.zeros(len(P), bool)
    used[I.ravel()] = True
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(used.sum())
    P, N, UV, J, W = P[used], N[used], UV[used], J[used], W[used]
    I = remap[I]

    # Animations.
    anims = {}
    for a in js["animations"]:
        ch = {}
        for c in a["channels"]:
            s = a["samplers"][c["sampler"]]
            ch[(c["target"]["node"], c["target"]["path"])] = (accessor(js, b, s["input"])[:, 0].astype(np.float64),
                                                              accessor(js, b, s["output"]).astype(np.float64))
        anims[a["name"]] = ch
    rig = Rig(js, anims)

    # 2. Feet: the tilt that levels the idle's soles, as a local correction.
    dom = J[np.arange(len(J)), W.argmax(1)]
    corr = {}
    for side in ("Left", "Right"):
        foot = names["mixamorig:%sFoot" % side]
        ids = [i for i, k in enumerate(joints) if js["nodes"][k]["name"].startswith("mixamorig:" + side)
               and ("Foot" in js["nodes"][k]["name"] or "Toe" in js["nodes"][k]["name"])]
        sole = np.isin(dom, ids) & (P[:, 1] < 0.012)
        normals = [sole_normal(rig, joints, ibm, P, J, W, sole, "Idle_9", t) for t in (0.0, 0.5, 1.0, 1.5)]
        n0 = np.mean(normals, 0)
        n0 /= np.linalg.norm(n0)
        axis = np.cross(n0, [0.0, 1.0, 0.0])
        ang = np.arcsin(np.linalg.norm(axis))
        axis /= np.linalg.norm(axis)
        G = rig.globals("Idle_9", 0.0)[foot][:3, :3]
        Gq = mat_q(G / np.linalg.norm(G, axis=0))
        Gi = Gq * np.array([-1, -1, -1, 1.0])
        world = np.r_[axis * np.sin(ang / 2), np.cos(ang / 2)]
        corr[foot] = qmul(qmul(Gi, world), Gq)
        after = sole_normal(rig, joints, ibm, P, J, W, sole, "Idle_9", 0.0, {foot: corr[foot]})
        print("%s foot: soles %.1f deg off level in the idle -> %.1f deg" % (side, np.degrees(ang), np.degrees(np.arccos(after[1]))))
    for clip in anims.values():
        for (node, path), (tin, out) in list(clip.items()):
            if path == "rotation" and node in corr:
                clip[(node, path)] = (tin, qmul(out, corr[node][None, :]))

    # 3. Clip names, Fall2.
    jump = anims["Regular_Jump"]
    fall2 = {}
    keys = 9
    times = np.linspace(0.0, FALL2_LEN, keys * 2 - 1)
    src_t = np.r_[np.linspace(FALL2_FROM, FALL2_TO, keys), np.linspace(FALL2_TO, FALL2_FROM, keys)[1:]]
    for (node, path), (tin, out) in jump.items():
        vals = np.array([sample(tin, out, t, path == "rotation") for t in src_t])
        fall2[(node, path)] = (times, vals)
    clips = {RENAME[k]: v for k, v in anims.items() if k in RENAME}
    clips["Fall2"] = fall2

    # Write.
    w = Writer()
    # Images and the skin's inverse binds are copied as they are.
    for img in js["images"]:
        bv = js["bufferViews"][img["bufferView"]]
        img["bufferView"] = w.view(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    skin["inverseBindMatrices"] = w.acc(accessor(js, b, skin["inverseBindMatrices"]).astype(np.float32), "MAT4")
    attrs = {
        "POSITION": w.acc(P.astype(np.float32), "VEC3", True, 34962),
        "NORMAL": w.acc((N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)).astype(np.float32), "VEC3", target=34962),
        "TEXCOORD_0": w.acc(UV.astype(np.float32), "VEC2", target=34962),
        "JOINTS_0": w.acc(J.astype(np.uint16), "VEC4", target=34962),
        "WEIGHTS_0": w.acc((W / W.sum(1, keepdims=True)).astype(np.float32), "VEC4", target=34962),
    }
    prim["attributes"] = attrs
    prim["indices"] = w.acc(I.reshape(-1).astype(np.uint32), "SCALAR", target=34963)
    js["animations"] = []
    for name, ch in clips.items():
        a = {"name": name, "channels": [], "samplers": []}
        for (node, path), (tin, out) in sorted(ch.items()):
            a["samplers"].append({"input": w.acc(tin.astype(np.float32)[:, None], "SCALAR", True),
                                  "output": w.acc(out.astype(np.float32), "VEC4" if path == "rotation" else "VEC3"),
                                  "interpolation": "LINEAR"})
            a["channels"].append({"sampler": len(a["samplers"]) - 1, "target": {"node": node, "path": path}})
        js["animations"].append(a)
    js["bufferViews"] = w.views
    js["accessors"] = w.accessors
    js["buffers"] = [{"byteLength": len(w.buf)}]
    return js, w.buf


def sole_normal(rig, joints, ibm, P, J, W, mask, clip, t, corr=None):
    G = rig.globals(clip, t, corr)
    mats = np.array([G[k] @ ibm[i] for i, k in enumerate(joints)])
    p = np.c_[P[mask], np.ones(mask.sum())]
    q = np.zeros((mask.sum(), 3))
    for k in range(4):
        q += W[mask][:, k:k + 1] * np.einsum("nij,nj->ni", mats[J[mask][:, k]], p)[:, :3]
    A = np.c_[q[:, 0], q[:, 2], np.ones(len(q))]
    k = np.linalg.lstsq(A, q[:, 1], rcond=None)[0]
    n = np.array([-k[0], 1.0, -k[1]])
    return n / np.linalg.norm(n)


def remove_halo(P, I):
    """Drops the separate ring of geometry floating above the head."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    _, inv = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    inv = inv.ravel()
    T = inv[I]
    n = inv.max() + 1
    r = np.r_[T[:, 0], T[:, 1], T[:, 2]]
    c = np.r_[T[:, 1], T[:, 2], T[:, 0]]
    _, lab = connected_components(coo_matrix((np.ones(len(r)), (r, c)), shape=(n, n)), directed=False)
    vl = lab[inv]
    halo = [k for k in np.unique(vl) if P[vl == k][:, 1].min() > 1.6]
    m = np.isin(vl, halo)
    q = P[m]
    cen = q.mean(0)
    nrm = np.linalg.svd(q - cen)[2][2]
    d = q - cen
    rad = np.linalg.norm(d - np.outer(d @ nrm, nrm), axis=1)
    print("halo removed: %d triangles; centre %s, normal %s, radius %.3f..%.3f" % (
        m[I].any(1).sum(), np.round(cen, 4), np.round(nrm, 3), np.percentile(rad, 1), np.percentile(rad, 99)))
    return I[~m[I].any(1)]


def clip_mesh(P, N, UV, J, W, I, d, region):
    """Removes geometry with d > 0 (inside `region`), clipping crossing
    triangles at d = 0. New rim vertices are shared per edge."""
    out_v = (d > 0) & region
    tri_out = out_v[I]
    keep = ~tri_out.any(1)
    cross = tri_out.any(1) & ~tri_out.all(1)
    P, N, UV, J, W = list(P), list(N), list(UV), list(J), list(W)
    edge_v = {}

    def cut(i, k):
        key = (min(i, k), max(i, k))
        if key not in edge_v:
            f = d[i] / (d[i] - d[k])
            P.append(P[i] + (P[k] - P[i]) * f)
            N.append(N[i] + (N[k] - N[i]) * f)
            UV.append(UV[i] + (UV[k] - UV[i]) * f)
            inside = i if d[i] <= 0 else k
            J.append(J[inside])
            W.append(W[inside])
            edge_v[key] = len(P) - 1
        return edge_v[key]

    new = []
    for tri in I[cross]:
        poly = []
        for e in range(3):
            a, c = tri[e], tri[(e + 1) % 3]
            ina, inc = not out_v[a], not out_v[c]
            if ina:
                poly.append(a)
            if ina != inc:
                poly.append(cut(a, c))
        for k in range(1, len(poly) - 1):
            new.append([poly[0], poly[k], poly[k + 1]])
    I2 = np.concatenate([I[keep], np.array(new, np.int64).reshape(-1, 3)])
    return (np.array(P), np.array(N), np.array(UV), np.array(J), np.array(W), I2,
            int(tri_out.any(1).sum()))


def build():
    js, buf = build_prep()
    tmp = OUT.replace(".glb", "_prep.tmp.glb")
    red = OUT.replace(".glb", "_red.tmp.glb")
    write_glb(tmp, js, buf)
    gp = os.environ.get("GLTFPACK", "gltfpack")
    subprocess.run([gp, "-i", tmp, "-o", red, "-si", "0.6", "-slb", "-kn", "-km", "-noq"], check=True)
    subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "transplant_animations.py"), tmp, red, OUT], check=True)
    os.remove(tmp)
    os.remove(red)
    print("wrote", OUT)


if __name__ == "__main__":
    build()
