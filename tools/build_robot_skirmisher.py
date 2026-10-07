#!/usr/bin/env python3
"""Builds the game-ready agile skirmisher robot (third enemy) from the untouched source:

    python3 tools/build_robot_skirmisher.py      (needs numpy, Pillow, pymeshlab)

  in:  assets/enemies/robot_skirmisher/source/robot_skirmisher_source.glb
       (never modified; the folder is .gdignore'd, so it isn't imported or
       exported)
  out: assets/enemies/robot_skirmisher/robot_skirmisher.glb       (game model)
       assets/enemies/robot_skirmisher/robot_skirmisher_far.glb   (distant LOD)

The source is one 62k-triangle skinned mesh on a Mixamo rig with a baked
2048 px texture set. What changes (all reproducible from here):

  * Geometry: texture-aware quadric decimation (MeshLab) to ~16k triangles,
    run per bone group with the group borders locked (no collapse joins
    vertices driven by different bones, so nothing stretches or spikes when
    joints bend). Vertices are never moved (only collapsed onto existing
    ones), so every kept vertex keeps its exact source position, normal, UV
    and skin weights. The skeleton, bind poses and skin weights are the
    source's.
  * Break-apart sections, prepared here (nothing is cut at runtime): every
    triangle goes to the body section its bones belong to - Head, Torso,
    Left_Arm, Right_Arm, Left_Leg, Right_Leg - each its own mesh node
    (same skin, same material). Every opening a detached section would show
    (its cuts, and the open ends of the source's overlapping shells that the
    neighbouring parts hide) is sealed by a shallow, recessed dark cap (own
    "Interior" material, double-sided, skinned like its rim), so no detached
    part is ever hollow.
  * Animations: copied from the source byte for byte, except where the
    clips would fight gameplay (the game moves and turns the body):
      - turn clips: the hips' heading change and travel are taken out (the
        steps, lean and arm swing stay); the removed heading curve is
        written to scripts/enemies/robot_skirmisher_motion.gd so the game
        turns the body in step with the feet;
      - the leaping punch (used as a dive): its forward travel is taken out
        and written to the same file (the game moves the body along it);
        its height (the leap) stays.
    The deaths keep their own short slides.
  * Textures: 1024 px JPEG (the game imports them at 1024 anyway).
  * Far LOD: the same decimation at ~4k triangles, one mesh, no textures or
    clips (the game skins it to the main skeleton with the main material).
"""
import io
import json
import os
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIR = os.path.join(ROOT, "assets/enemies/robot_skirmisher")
SRC = os.path.join(DIR, "source/robot_skirmisher_source.glb")
OUT = os.path.join(DIR, "robot_skirmisher.glb")
OUT_FAR = os.path.join(DIR, "robot_skirmisher_far.glb")

TRIANGLES = 16000
FAR_TRIANGLES = 4000
TEXTURE_SIZE = 1024

# Bone -> body section (the Mixamo names, without the "mixamorig:" prefix).
SECTIONS = ["Torso", "Head", "Left_Arm", "Right_Arm", "Left_Leg", "Right_Leg"]
BONE_SECTION = {
    "Hips": "Torso", "Spine": "Torso", "Spine1": "Torso", "Spine2": "Torso",
    "LeftShoulder": "Torso", "RightShoulder": "Torso",
    "Neck": "Head", "Head": "Head", "HeadTop_End": "Head", "headfront": "Head",
    "LeftArm": "Left_Arm", "LeftForeArm": "Left_Arm", "LeftHand": "Left_Arm", "LeftHandMiddle4": "Left_Arm",
    "RightArm": "Right_Arm", "RightForeArm": "Right_Arm", "RightHand": "Right_Arm", "RightHandMiddle4": "Right_Arm",
    "LeftUpLeg": "Left_Leg", "LeftLeg": "Left_Leg", "LeftFoot": "Left_Leg", "LeftToeBase": "Left_Leg", "LeftToe_End": "Left_Leg",
    "RightUpLeg": "Right_Leg", "RightLeg": "Right_Leg", "RightFoot": "Right_Leg", "RightToeBase": "Right_Leg", "RightToe_End": "Right_Leg",
}
# Smoothing passes over the triangle -> section assignment (removes single
# stray triangles so each cut is one clean ring).
SMOOTH_PASSES = 3
# How far a cap's centre sits back into its section (fraction of its radius).
CAP_RECESS = 0.2
# A ring whose own triangles face against the cap (mean dot below this) is
# a plate's outline, not a hole.
PLATE_FACING = -0.6
# Rings of only 2-3 edges are capped only up to this radius (m).
CAP_SMALL_RADIUS = 0.03
INTERIOR_COLOR = [0.045, 0.045, 0.05, 1.0]

# Turn clips: heading change and travel moved out of the clip.
TURNS = ["Idle_Turn_Left", "Idle_Turn_Right", "Run_Turn_Left", "Run_Turn_Right",
         "Walk_Turn_Left", "Walk_Turn_Right", "Walk_Turn_Left_with_Weapon",
         "Walk_Turn_Right_Idle_Style"]
# Clips whose forward travel the game drives instead.
TRAVEL = ["Jumping_Punch"]
MOTION_OUT = os.path.join(ROOT, "scripts/enemies/robot_skirmisher_motion.gd")
MOTION_RATE = 15.0  # samples per second in the motion file

# ---------------------------------------------------------------- glTF io
CT = {5126: ("<f4", 4), 5123: ("<u2", 2), 5121: ("u1", 1), 5125: ("<u4", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    g = json.loads(d[20:20 + jl])
    bl = struct.unpack("<I", d[20 + jl:24 + jl])[0]
    return g, d[28 + jl:28 + jl + bl]


def read_acc(g, B, i):
    a = g["accessors"][i]
    v = g["bufferViews"][a["bufferView"]]
    dt, sz = CT[a["componentType"]]
    n = NC[a["type"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", sz * n)
    raw = np.frombuffer(B, dtype=np.uint8, count=stride * (a["count"] - 1) + sz * n, offset=off)
    out = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], sz * n), strides=(stride, 1)).copy()
    out = out.view(dt).reshape(a["count"], n)
    if a.get("normalized"):
        out = out.astype(np.float32) / float(np.iinfo(out.dtype).max)
    return out


class Writer:
    def __init__(self):
        self.buf = bytearray()
        self.views = []
        self.accessors = []

    def blob(self, data, target=None):
        while len(self.buf) % 4:
            self.buf.append(0)
        v = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.buf += data
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, arr, ctype, atype, normalized=False, target=None, minmax=False):
        dt = CT[ctype][0]
        a = np.ascontiguousarray(arr.astype(dt))
        acc = {"bufferView": self.blob(a.tobytes(), target), "componentType": ctype,
               "count": int(a.shape[0]), "type": atype}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in a.reshape(a.shape[0], -1).min(0)]
            acc["max"] = [float(x) for x in a.reshape(a.shape[0], -1).max(0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def save(self, path, gl):
        gl["accessors"] = self.accessors
        gl["bufferViews"] = self.views
        gl["buffers"] = [{"byteLength": len(self.buf)}]
        js = json.dumps(gl, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        while len(self.buf) % 4:
            self.buf.append(0)
        total = 12 + 8 + len(js) + 8 + len(self.buf)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(self.buf), 0x004E4942) + bytes(self.buf))
        return total


# ---------------------------------------------------------------- source mesh
class Source:
    def __init__(self, g, B):
        pr = g["meshes"][0]["primitives"][0]
        at = pr["attributes"]
        self.P = read_acc(g, B, at["POSITION"]).astype(np.float64)
        self.N = read_acc(g, B, at["NORMAL"]).astype(np.float64)
        self.UV = read_acc(g, B, at["TEXCOORD_0"]).astype(np.float64)
        self.J = read_acc(g, B, at["JOINTS_0"]).astype(np.int64)
        self.W = read_acc(g, B, at["WEIGHTS_0"]).astype(np.float64)
        self.I = read_acc(g, B, pr["indices"]).reshape(-1, 3).astype(np.int64)
        # Weld UV/normal seam copies - but not vertices of different shells
        # that merely coincide (they follow different bones): the key is the
        # position plus the skin weights.
        wfull = np.zeros((len(self.P), 64))
        for k in range(4):
            np.add.at(wfull, (np.arange(len(self.P)), self.J[:, k]), self.W[:, k])
        key = np.hstack([np.round(self.P * 1e5), np.round(wfull * 50)]).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        self.inv = inv.ravel()
        self.V = self.P[first]          # welded positions
        self.F = self.inv[self.I]       # welded triangles
        # Welded vertex -> its source vertices (the UV/normal seam copies).
        order = np.argsort(self.inv, kind="stable")
        bounds = np.searchsorted(self.inv[order], np.arange(len(self.V) + 1))
        self.copies = [order[bounds[k]:bounds[k + 1]] for k in range(len(self.V))]
        self.key = {}
        for i, k in enumerate(np.round(self.V * 1e5).astype(np.int64).tolist()):
            self.key.setdefault(tuple(k), []).append(i)

    def welded_of(self, positions, hint=None):
        """Welded source vertex for each position (exact, else nearest).
        Where shells coincide, `hint` (the source vertex the decimator kept)
        picks the right one."""
        out = np.empty(len(positions), np.int64)
        miss = []
        for i, k in enumerate(np.round(positions * 1e5).astype(np.int64).tolist()):
            w = self.key.get(tuple(k))
            if w is None:
                miss.append(i)
            elif len(w) == 1 or hint is None:
                out[i] = w[0]
            else:
                out[i] = hint[i] if hint[i] in w else w[0]
        for i in miss:
            out[i] = int(np.argmin(((self.V - positions[i]) ** 2).sum(1)))
        return out, len(miss)


# Bone groups the decimation never collapses across (a triangle joining two
# of them would stretch when the joint bends).
BONE_GROUP = {
    "Hips": "Hips", "Spine": "Spine", "Spine1": "Spine1", "Spine2": "Spine2",
    "Neck": "Neck", "Head": "Head", "HeadTop_End": "Head", "headfront": "Head",
    "LeftShoulder": "LShoulder", "RightShoulder": "RShoulder",
    "LeftArm": "LArm", "LeftForeArm": "LForeArm", "LeftHand": "LHand", "LeftHandMiddle4": "LHand",
    "RightArm": "RArm", "RightForeArm": "RForeArm", "RightHand": "RHand", "RightHandMiddle4": "RHand",
    "LeftUpLeg": "LUpLeg", "LeftLeg": "LLeg", "LeftFoot": "LFoot", "LeftToeBase": "LFoot", "LeftToe_End": "LFoot",
    "RightUpLeg": "RUpLeg", "RightLeg": "RLeg", "RightFoot": "RFoot", "RightToeBase": "RFoot", "RightToe_End": "RFoot",
}


def decimate(src, target, joint_group):
    """[positions, triangles, wedge uvs (T*3, 2)] at about `target` triangles.
    Each bone group's triangles are simplified on their own with their
    borders locked, so no collapse ever joins vertices that different bones
    drive (that is what makes decimated skinned meshes tear or spike when a
    joint bends)."""
    import pymeshlab as ml
    # Dominant bone group per welded vertex, then per triangle (majority).
    G = joint_group.max() + 1
    vg = np.zeros((len(src.V), G))
    for k in range(4):
        np.add.at(vg, (src.inv, joint_group[src.J[:, k]]), src.W[:, k])
    vgroup = vg.argmax(1)
    tg = vgroup[src.F]
    tri_group = np.where(tg[:, 1] == tg[:, 2], tg[:, 1], tg[:, 0])
    # Coincident vertices of different shells get a tiny offset each (tens of
    # micrometres) so they stay apart through MeshLab and every output
    # vertex maps back to exactly one source vertex.
    rank = np.zeros(len(src.V), np.int64)
    for ids in src.key.values():
        for r, i in enumerate(ids):
            rank[i] = r
    Vo = src.V + np.outer(rank, [2e-5, 1e-5, 0.0])
    lookup = {tuple(k): i for i, k in enumerate(np.round(Vo * 1e6).astype(np.int64).tolist())}
    Vs, Fs, Ws, Ids = [], [], [], []
    base = 0
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "m.mtl"), "w").write("newmtl M\nmap_Kd t.png\n")
        Image.new("RGB", (8, 8)).save(os.path.join(d, "t.png"))
        for gi in range(G):
            sel = np.nonzero(tri_group == gi)[0]
            if len(sel) == 0:
                continue
            F = src.F[sel]
            I = src.I[sel]
            used, Fl = np.unique(F, return_inverse=True)
            Fl = Fl.reshape(-1, 3) + 1
            obj = os.path.join(d, "g%d.obj" % gi)
            with open(obj, "w") as f:
                f.write("mtllib m.mtl\n")
                f.write("".join("v %.9f %.9f %.9f\n" % tuple(v) for v in Vo[used]))
                f.write("".join("vt %.7f %.7f\n" % (src.UV[i][0], 1.0 - src.UV[i][1]) for i in I.reshape(-1)))
                f.write("usemtl M\n")
                f.write("".join("f %d/%d %d/%d %d/%d\n" % (Fl[t, 0], 3 * t + 1, Fl[t, 1], 3 * t + 2, Fl[t, 2], 3 * t + 3)
                                for t in range(len(Fl))))
            ms = ml.MeshSet()
            ms.load_new_mesh(obj)
            want = max(int(round(target * len(sel) / len(src.F))), min(len(sel), 24))
            if want < ms.current_mesh().face_number():
                ms.meshing_decimation_quadric_edge_collapse_with_texture(
                    targetfacenum=want, optimalplacement=False, preserveboundary=True,
                    boundaryweight=10.0, preservenormal=True, qualitythr=0.5)
            m = ms.current_mesh()
            uv = m.wedge_tex_coord_matrix().copy()
            uv[:, 1] = 1.0 - uv[:, 1]
            out_v = m.vertex_matrix()
            ids = np.array([lookup.get(tuple(k), -1) for k in np.round(out_v * 1e6).astype(np.int64).tolist()])
            Vs.append(np.where(ids[:, None] >= 0, src.V[np.maximum(ids, 0)], out_v))
            Ids.append(ids)
            Fs.append(m.face_matrix().astype(np.int64) + base)
            Ws.append(uv)
            base += len(out_v)
    return np.concatenate(Vs), np.concatenate(Fs), np.concatenate(Ws), np.concatenate(Ids)


def rebuild(src, V, F, WUV, ids):
    """Final vertex arrays from a decimated mesh: each (position, uv) wedge
    becomes one vertex with the source's normal and skin weights there."""
    wv, missing = src.welded_of(V)
    wv = np.where(ids >= 0, ids, wv)
    missing = int((ids < 0).sum())
    key = np.hstack([F.reshape(-1, 1), np.round(WUV * 1e5).astype(np.int64)])
    uniq, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    vi = uniq[:, 0]
    uv = WUV[first]
    pos = V[vi]
    nrm = np.zeros((len(uniq), 3))
    J = np.zeros((len(uniq), 4), np.int64)
    W = np.zeros((len(uniq), 4))
    for k in range(len(uniq)):
        cands = src.copies[wv[vi[k]]]
        # The source copy with the nearest UV carries this wedge's normal.
        c = cands[np.argmin(((src.UV[cands] - uv[k]) ** 2).sum(1))]
        nrm[k] = src.N[c]
        J[k] = src.J[c]
        W[k] = src.W[c]
    tris = inv.reshape(-1, 3)
    # Drop triangles that collapsed to a line.
    good = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 0] != tris[:, 2])
    return {"pos": pos, "nrm": nrm, "uv": uv, "J": J, "W": W, "tris": tris[good], "welded": vi,
            "missing": missing}


# ---------------------------------------------------------------- sections
def assign_sections(m, joint_section):
    """Section index per triangle (by the bones its vertices follow)."""
    S = len(SECTIONS)
    per_v = np.zeros((len(m["pos"]), S))
    for k in range(4):
        np.add.at(per_v, (np.arange(len(per_v)), joint_section[m["J"][:, k]]), m["W"][:, k])
    # Sum over the welded position (seam copies agree).
    wsum = np.zeros((m["welded"].max() + 1, S))
    np.add.at(wsum, m["welded"], per_v)
    T = m["tris"]
    score = wsum[m["welded"][T]].sum(1)
    sec = score.argmax(1)
    # Neighbour smoothing (edge-adjacent triangles, welded).
    wt = m["welded"][T]
    edges = {}
    for t in range(len(T)):
        for e in range(3):
            a, b = wt[t, e], wt[t, (e + 1) % 3]
            edges.setdefault((min(a, b), max(a, b)), []).append(t)
    nb = [[] for _ in range(len(T))]
    for ts in edges.values():
        for t in ts:
            nb[t].extend(x for x in ts if x != t)
    for _ in range(SMOOTH_PASSES):
        new = sec.copy()
        for t in range(len(T)):
            if not nb[t]:
                continue
            votes = np.bincount(sec[nb[t]], minlength=S)
            if votes[sec[t]] == 0 and votes.max() >= 2:
                new[t] = votes.argmax()
        sec = new
    return sec


def section_mesh(m, sec, s):
    """[vertex arrays, triangles] of section `s` plus its cap triangles."""
    T = m["tris"][sec == s]
    used = np.unique(T)
    remap = -np.ones(len(m["pos"]), np.int64)
    remap[used] = np.arange(len(used))
    out = {k: m[k][used] for k in ("pos", "nrm", "uv", "J", "W")}
    tris = remap[T]
    caps = cap_holes(m, sec, s)
    return out, tris, caps


def cap_holes(m, sec, s):
    """Caps over every hole of the section that would show once it is on
    its own: the cuts it shares with other sections, and the open ends of
    the source's own shells (hidden inside the neighbouring parts while the
    robot is whole). Each boundary edge a->b gets the fan triangle
    (b, a, centre), the centre recessed into the section, so the cap
    continues the surface's winding and closes the hole. A plain plate's
    outline (its triangles lie inside the ring, facing against the cap) is
    left alone - capping it would only double the plate."""
    wt = m["welded"][m["tris"]]
    own = np.nonzero(sec == s)[0]
    directed = {}
    tri_n = {}
    for t in own:
        pa, pb, pc = (m["pos"][m["tris"][t, k]] for k in range(3))
        n = np.cross(pb - pa, pc - pa)
        ln = np.linalg.norm(n)
        for e in range(3):
            a, b = int(wt[t, e]), int(wt[t, (e + 1) % 3])
            directed[(a, b)] = (int(m["tris"][t, e]), int(m["tris"][t, (e + 1) % 3]))
            tri_n[(a, b)] = n / ln if ln > 0 else n
    bnd = [(a, b, verts) for (a, b), verts in directed.items() if (b, a) not in directed]
    if not bnd:
        return []
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b, _ in bnd:
        parent[find(a)] = find(b)
    rings = {}
    for e in bnd:
        rings.setdefault(find(e[0]), []).append(e)
    caps = []
    for edges in rings.values():
        if len(edges) < 2:
            continue  # a lone edge: nothing to close
        rim = np.array([m["pos"][v] for _, _, (va, vb) in edges for v in (va, vb)])
        c = rim.mean(0)
        radius = float(np.sqrt(((rim - c) ** 2).sum(1)).mean())
        n = np.zeros(3)
        for _, _, (va, vb) in edges:
            pa, pb = m["pos"][va], m["pos"][vb]
            n += np.cross(pa - pb, c - pb)
        if np.linalg.norm(n) < 1e-9:
            continue
        n /= np.linalg.norm(n)  # out of the section
        facing = float(np.mean([np.dot(tri_n[(a, b)], n) for a, b, _ in edges]))
        if facing < PLATE_FACING:
            continue  # a plate's outline, not a hole
        if len(edges) < 4 and radius > CAP_SMALL_RADIUS:
            continue  # a stray 2-3 edge gap across something big: leave it
        caps.append({"edges": [(va, vb) for _, _, (va, vb) in edges],
                     "centre": c - n * radius * CAP_RECESS, "normal": n})
    return caps


def cap_arrays(m, caps):
    """Vertex arrays + triangles for a section's caps (rim vertices copy the
    rim's skin weights; the centre takes the rim's strongest bones)."""
    pos, nrm, uv, J, W, tris = [], [], [], [], [], []
    for cap in caps:
        rim = sorted({v for e in cap["edges"] for v in e})
        local = {}
        for v in rim:
            local[v] = len(pos)
            pos.append(m["pos"][v])
            nrm.append(cap["normal"])
            uv.append((0.0, 0.0))
            J.append(m["J"][v])
            W.append(m["W"][v])
        acc = {}
        for v in rim:
            for k in range(4):
                if m["W"][v, k] > 0:
                    acc[int(m["J"][v, k])] = acc.get(int(m["J"][v, k]), 0.0) + float(m["W"][v, k])
        top = sorted(acc.items(), key=lambda x: -x[1])[:4]
        tot = sum(w for _, w in top)
        cj = [j for j, _ in top] + [0] * (4 - len(top))
        cw = [w / tot for _, w in top] + [0.0] * (4 - len(top))
        ci = len(pos)
        pos.append(cap["centre"])
        nrm.append(cap["normal"])
        uv.append((0.0, 0.0))
        J.append(cj)
        W.append(cw)
        for va, vb in cap["edges"]:
            tris.append((local[vb], local[va], ci))
    return {"pos": np.array(pos), "nrm": np.array(nrm), "uv": np.array(uv),
            "J": np.array(J, np.int64), "W": np.array(W)}, np.array(tris, np.int64)


def primitive(W, arr, tris, material):
    w = arr["W"] / np.maximum(arr["W"].sum(1, keepdims=True), 1e-9)
    # Normalised bytes; the rounding error goes onto the biggest weight.
    wb = np.round(w * 255).astype(np.int64)
    big = wb.argmax(1)
    wb[np.arange(len(wb)), big] += 255 - wb.sum(1)
    n = arr["nrm"] / np.maximum(np.linalg.norm(arr["nrm"], axis=1, keepdims=True), 1e-9)
    big_index = len(arr["pos"]) > 65535
    return {"attributes": {
        "POSITION": W.acc(arr["pos"], 5126, "VEC3", target=34962, minmax=True),
        "NORMAL": W.acc(n, 5126, "VEC3", target=34962),
        "TEXCOORD_0": W.acc(arr["uv"], 5126, "VEC2", target=34962),
        "JOINTS_0": W.acc(arr["J"], 5121, "VEC4", target=34962),
        "WEIGHTS_0": W.acc(wb, 5121, "VEC4", normalized=True, target=34962)},
        "indices": W.acc(tris.reshape(-1), 5125 if big_index else 5123, "SCALAR", target=34963),
        "material": material}


# ---------------------------------------------------------------- motion file
def resample(t, vals):
    """Values at MOTION_RATE Hz from 0 to the clip's last key."""
    ts = np.arange(0.0, t[-1] + 1e-6, 1.0 / MOTION_RATE)
    return np.stack([np.interp(ts, t, vals[:, k]) for k in range(vals.shape[1])], 1)


def write_motion(turns, travel):
    def arr(a):
        return "[" + ", ".join("%.4f" % v for v in a) + "]"
    lines = ["class_name RobotSkirmisherMotion",
             "## GENERATED by tools/build_robot_skirmisher.py - do not edit.",
             "## Motion taken out of the skirmisher's clips so the game can drive the",
             "## body with it instead, sampled at RATE Hz from the clip's start:",
             "## TURN_YAW: heading change (rad, about +Y) of each turn clip;",
             "## TRAVEL_X / TRAVEL_Z: model-space hips travel (m) of the dive clip.",
             "",
             "const RATE := %.1f" % MOTION_RATE,
             "const TURN_YAW := {"]
    for k, v in turns.items():
        lines.append('\t&"%s": %s,' % (k, arr(v[:, 0])))
    lines.append("}")
    lines.append("const TRAVEL_X := {")
    for k, v in travel.items():
        lines.append('\t&"%s": %s,' % (k, arr(v[:, 0])))
    lines.append("}")
    lines.append("const TRAVEL_Z := {")
    for k, v in travel.items():
        lines.append('\t&"%s": %s,' % (k, arr(v[:, 1])))
    lines.append("}")
    lines += ["", "", "## Linear sample of a motion curve at `t` seconds into its clip.",
              "static func sample(curve: Array, t: float) -> float:",
              "\tif curve.is_empty():",
              "\t\treturn 0.0",
              "\tvar f := clampf(t * RATE, 0.0, curve.size() - 1.0)",
              "\tvar i := int(f)",
              "\tif i >= curve.size() - 1:",
              "\t\treturn curve[curve.size() - 1]",
              "\treturn lerpf(curve[i], curve[i + 1], f - i)",
              ""]
    open(MOTION_OUT, "w").write("\n".join(lines))


# ---------------------------------------------------------------- build
def main():
    g, B = load(SRC)
    src = Source(g, B)
    skin = g["skins"][0]
    joint_names = [g["nodes"][j]["name"].split(":")[-1] for j in skin["joints"]]
    joint_section = np.array([SECTIONS.index(BONE_SECTION[n]) for n in joint_names])
    groups = sorted(set(BONE_GROUP.values()))
    joint_group = np.array([groups.index(BONE_GROUP[n]) for n in joint_names])

    # Textures: 1024 px JPEG.
    images = []
    for im in g["images"]:
        v = g["bufferViews"][im["bufferView"]]
        data = B[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        img = Image.open(io.BytesIO(data)).convert("RGB").resize((TEXTURE_SIZE, TEXTURE_SIZE), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=94, subsampling=0)
        images.append({"name": im["name"], "mimeType": "image/jpeg",
                       "data": out.getvalue()})

    # --- main model
    V, F, WUV, ids = decimate(src, TRIANGLES, joint_group)
    m = rebuild(src, V, F, WUV, ids)
    sec = assign_sections(m, joint_section)
    W = Writer()
    cache = {}

    def keep(i):
        if i not in cache:
            a = g["accessors"][i]
            assert not a.get("normalized")
            cache[i] = W.acc(read_acc(g, B, i), a["componentType"], a["type"], False, None, "min" in a)
        return cache[i]

    mesh_node = next(i for i, n in enumerate(g["nodes"]) if "mesh" in n)
    nodes = json.loads(json.dumps(g["nodes"]))
    root = next(i for i, n in enumerate(nodes) if mesh_node in n.get("children", []))
    nodes[root]["children"].remove(mesh_node)
    nodes[mesh_node] = {"name": "_unused"}
    meshes = []
    stats = []
    for s, name in enumerate(SECTIONS):
        arr, tris, caps = section_mesh(m, sec, s)
        prims = [primitive(W, arr, tris, 0)]
        ca, ct = cap_arrays(m, caps)
        if len(ct):
            prims.append(primitive(W, ca, ct, 1))
        meshes.append({"name": name, "primitives": prims})
        nodes.append({"name": name, "mesh": len(meshes) - 1, "skin": 0})
        nodes[root]["children"].insert(0, len(nodes) - 1)
        stats.append(f"{name} {len(tris)}+{len(ct)} ({len(caps)} cap{'s' if len(caps) != 1 else ''})")
    # The unused source mesh node stays as an empty placeholder (keeps every
    # other node index - and so the skin and animation targets - unchanged).
    nodes[root]["children"] = [c for c in nodes[root]["children"] if c != mesh_node]

    names = {n["name"]: i for i, n in enumerate(g["nodes"])}
    hips = names["mixamorig:Hips"]
    rest_t = g["nodes"][hips]["translation"]
    motion_turns, motion_travel = {}, {}
    anims = []
    for an in g["animations"]:
        na = {"name": an["name"], "samplers": [], "channels": []}
        for ch in an["channels"]:
            smp = an["samplers"][ch["sampler"]]
            inp = keep(smp["input"])
            on_hips = ch["target"]["node"] == hips
            path = ch["target"]["path"]
            name = an["name"]
            if on_hips and path == "translation" and (name in TURNS or name in TRAVEL):
                t = read_acc(g, B, smp["input"])[:, 0]
                vals = read_acc(g, B, smp["output"]).copy()
                if name in TRAVEL:
                    motion_travel[name] = resample(t, vals[:, [0, 2]] - vals[0, [0, 2]])
                # Hips stay over the body's centre, like the other clips.
                vals[:, 0] = rest_t[0]
                vals[:, 2] = rest_t[2]
                out = W.acc(vals, 5126, "VEC3")
            elif on_hips and path == "rotation" and name in TURNS:
                t = read_acc(g, B, smp["input"])[:, 0]
                q = read_acc(g, B, smp["output"]).astype(np.float64)
                # Swing-twist: the twist about the vertical is the heading.
                yaw = np.unwrap(2.0 * np.arctan2(q[:, 1], q[:, 3]))
                c, s_ = np.cos(-yaw / 2), np.sin(-yaw / 2)
                # q' = Ry(-yaw) * q
                x, y, z, w = q.T
                q2 = np.stack([c * x + s_ * z, c * y + s_ * w, c * z - s_ * x, c * w - s_ * y], 1)
                motion_turns[name] = resample(t, (yaw - yaw[0]).reshape(-1, 1))
                out = W.acc(q2, 5126, "VEC4")
            else:
                out = keep(smp["output"])
            na["samplers"].append({"input": inp, "output": out, "interpolation": smp.get("interpolation", "LINEAR")})
            na["channels"].append({"sampler": len(na["samplers"]) - 1, "target": ch["target"]})
        anims.append(na)
    skins = [{"joints": skin["joints"], "inverseBindMatrices": keep(skin["inverseBindMatrices"]),
              **({"skeleton": skin["skeleton"]} if "skeleton" in skin else {})}]

    write_motion(motion_turns, motion_travel)
    for im in images:
        im["bufferView"] = W.blob(im.pop("data"))
    materials = [g["materials"][0],
                 {"name": "Interior", "doubleSided": True,
                  "pbrMetallicRoughness": {"baseColorFactor": INTERIOR_COLOR, "metallicFactor": 0.7,
                                           "roughnessFactor": 0.55}}]
    gl = {"asset": {"version": "2.0", "generator": "CONSTRUCT-ERROR tools/build_robot_skirmisher.py"},
          "scene": 0, "scenes": g["scenes"], "nodes": nodes, "meshes": meshes, "skins": skins,
          "animations": anims, "materials": materials, "textures": g["textures"], "images": images,
          "samplers": g["samplers"]}
    total = W.save(OUT, gl)
    print(f"{os.path.relpath(OUT, ROOT)}: {total:,} bytes; {len(m['tris'])} triangles, {len(m['pos'])} vertices "
          f"({m['missing']} snapped); sections: " + ", ".join(stats))

    # --- far LOD: one mesh, no textures/clips.
    V, F, WUV, ids = decimate(src, FAR_TRIANGLES, joint_group)
    f = rebuild(src, V, F, WUV, ids)
    W = Writer()
    cache.clear()
    nodes = json.loads(json.dumps(g["nodes"]))
    nodes[mesh_node]["name"] = "Body"
    meshes = [{"name": "Body", "primitives": [primitive(W, f, f["tris"], 0)]}]
    skins = [{"joints": skin["joints"], "inverseBindMatrices": keep(skin["inverseBindMatrices"]),
              **({"skeleton": skin["skeleton"]} if "skeleton" in skin else {})}]
    mat = {"name": g["materials"][0]["name"], "pbrMetallicRoughness": {"metallicFactor": 0.5}}
    gl = {"asset": {"version": "2.0", "generator": "CONSTRUCT-ERROR tools/build_robot_skirmisher.py"},
          "scene": 0, "scenes": g["scenes"], "nodes": nodes, "meshes": meshes, "skins": skins,
          "materials": [mat]}
    total = W.save(OUT_FAR, gl)
    print(f"{os.path.relpath(OUT_FAR, ROOT)}: {total:,} bytes; {len(f['tris'])} triangles, {len(f['pos'])} vertices")


if __name__ == "__main__":
    main()
