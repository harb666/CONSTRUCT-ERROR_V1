#!/usr/bin/env python3
"""Builds the game-ready agile skirmisher robot (third enemy) from the untouched source:

    python3 tools/build_robot_skirmisher.py      (needs numpy, scipy, Pillow,
                                                    meshoptimizer, xatlas)

  in:  assets/enemies/robot_skirmisher/source/robot_skirmisher_source.glb
       (never modified; the folder is .gdignore'd, so it isn't imported or
       exported)
  out: assets/enemies/robot_skirmisher/robot_skirmisher.glb       (game model)
       assets/enemies/robot_skirmisher/robot_skirmisher_far.glb   (distant LOD)

The source is one 62k-triangle skinned mesh on a Mixamo rig with a baked
2048 px texture set. What changes (all reproducible from here):

  * Geometry: reduced to ~16k triangles (meshoptimizer) on the welded
    source, vertices only ever collapsed onto existing ones (each kept
    vertex keeps its exact source position and skin weights), with every
    vertex on a border between bone groups locked and coincident shells of
    different parts kept apart (no collapse joins vertices driven by
    different bones, so nothing stretches or spikes when joints bend).
    Normals smooth up to CREASE_DEG, hard beyond. Skin weights are the
    source's (every part is rigidly bound to one bone).
  * Skeleton re-fit: the source's auto-rig put the joints up to 0.3 m off
    the parts they move (hips in front of the pelvis, spine at the chest
    plate, hip joints off-centre), so every rigid part swung about the
    wrong point and the parts drifted apart whenever a joint bent - legs
    detached from the pelvis, the torso floating (worst under the game's
    aim twist). Each joint is moved to where its part meets its parent part
    (JOINT_FIT); joint orientations and the mesh are unchanged and the bind
    poses follow.
  * Textures: the source's UVs are fragmented almost per triangle (84k UV
    vertices on 30k positions), so no reduction can keep them. The reduced
    mesh gets a new UV layout (xatlas) and the source's base colour,
    metal/roughness and normal maps are re-baked onto it (tools/mesh_bake.py:
    every texel takes the colour of the matching point on the source
    surface; the normal map carries the source's shading normal, normal map
    included, in the new tangent frames, exported with the mesh).
  * Break-apart sections, prepared here (nothing is cut at runtime): every
    triangle goes to the body section its bones belong to - Head, Torso,
    Left_Arm, Right_Arm, Left_Leg, Right_Leg - each its own mesh node
    (same skin, same material). Every opening a detached section would show
    (its cuts, and the open ends of the source's overlapping shells that the
    neighbouring parts hide) is sealed by a shallow, recessed dark cap (own
    "Interior" material, double-sided, skinned like its rim), so no detached
    part is ever hollow.
  * Animations: the clips' joint rotations are the source's. The hips
    track is re-based on the moved hips pivot (the pelvis moves exactly as
    before) and re-grounded per frame so the body's lowest point follows
    the clip's but never goes below the floor (the source clips sink the
    planted foot up to 15 cm into it); the other joints' tracks are their
    new rest offsets. Further changes where the clips would fight gameplay
    (the game moves and turns the body):
      - turn clips: the hips' heading change and travel are taken out (the
        steps, lean and arm swing stay); the removed heading curve is
        written to scripts/enemies/robot_skirmisher_motion.gd so the game
        turns the body in step with the feet;
      - the leaping punch (used as a dive): its forward travel is taken out
        and written to the same file (the game moves the body along it);
        its height (the leap) stays.
    The deaths keep their own short slides.
  * Far LOD: the same reduction at ~4k triangles, one mesh, no clips, with
    its own small baked colour texture (the game skins it to the main
    skeleton).
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_bake  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIR = os.path.join(ROOT, "assets/enemies/robot_skirmisher")
SRC = os.path.join(DIR, "source/robot_skirmisher_source.glb")
OUT = os.path.join(DIR, "robot_skirmisher.glb")
OUT_FAR = os.path.join(DIR, "robot_skirmisher_far.glb")

TRIANGLES = 16000
FAR_TRIANGLES = 4000
# Baked atlas: baked at ATLAS_BAKE px (charts padded for mip levels), then
# filtered down to these sizes (colour at full size; the normal and
# metal/roughness maps carry less fine detail).
ATLAS_BAKE = 2048
ATLAS_PADDING = 4
TEXTURE_SIZE = {"texture_0": 2048, "normal": 1024, "texture_0_metallic_roughness": 1024}
# Far LOD: its own small atlas (colour only).
FAR_ATLAS_BAKE = 1024
FAR_ATLAS_PADDING = 4
FAR_TEXTURE_SIZE = 512
JPEG_QUALITY = 94
# Normals: smooth across edges up to this angle, hard beyond.
CREASE_DEG = 40.0

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
        self.TAN = read_acc(g, B, at["TANGENT"]).astype(np.float64)
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


# Bone groups the reduction never collapses across (a triangle joining two
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


def vertex_groups(src, joint_group):
    """Dominant bone group per welded vertex, and per source triangle."""
    G = joint_group.max() + 1
    vg = np.zeros((len(src.V), G))
    for k in range(4):
        np.add.at(vg, (src.inv, joint_group[src.J[:, k]]), src.W[:, k])
    vgroup = vg.argmax(1)
    tg = vgroup[src.F]
    return vgroup, np.where(tg[:, 1] == tg[:, 2], tg[:, 1], tg[:, 0])


def lowpoly(src, target, joint_group, atlas_px, padding):
    """The game mesh: the source's shape at about `target` triangles, with a
    clean new UV layout (the source's own UVs are fragmented almost per
    triangle, so no reduction can keep them).

    Reduction (meshoptimizer) on the welded source: vertices are only ever
    collapsed onto existing ones, so every kept vertex has its exact source
    position and skin weights; vertices on a border between bone groups are
    locked, so no collapse joins vertices different bones drive (nothing
    stretches or spikes when a joint bends); coincident shells of different
    parts are kept apart. Normals: smooth up to CREASE_DEG, hard beyond.
    UVs: xatlas. The textures are then baked onto it (bake_textures)."""
    vgroup, _ = vertex_groups(src, joint_group)
    # Lock every position on a triangle spanning two groups.
    tg = vgroup[src.F]
    mixed = ~((tg[:, 0] == tg[:, 1]) & (tg[:, 1] == tg[:, 2]))
    lock = np.zeros(len(src.V), np.uint8)
    lock[src.F[mixed].ravel()] = 1
    rank = np.zeros(len(src.V), np.int64)
    for ids in src.key.values():
        for r, i in enumerate(ids):
            rank[i] = r
    Vo = src.V + np.outer(rank, [2e-5, 1e-5, 0.0])
    # Position-only metric (one dummy attribute with no weight).
    T = mesh_bake.simplify(src.F, Vo, np.zeros((len(Vo), 1)), np.zeros(1), lock, target)
    T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
    wid, cn, ct = mesh_bake.crease_split(src.V, T, CREASE_DEG)
    vmap, tris, uv = mesh_bake.unwrap(src.V[wid], cn, ct, atlas_px, padding)
    welded = wid[vmap]
    one = np.array([src.copies[w][0] for w in welded])
    nrm = cn[vmap]
    m = {"pos": src.V[welded], "nrm": nrm, "uv": uv, "J": src.J[one], "W": src.W[one], "tris": tris,
         "welded": welded, "locked": int(lock[np.unique(T)].sum())}
    m["tan"] = mesh_bake.tangents(m["pos"], nrm, uv, tris)
    gv = vgroup[welded]
    m["group"] = np.where(gv[tris[:, 1]] == gv[tris[:, 2]], gv[tris[:, 1]], gv[tris[:, 0]])
    return m


def bake_textures(src, m, images, joint_group, atlas_px, only=None):
    """The source's maps baked onto the lowpoly mesh's atlas: {image name:
    PIL image}."""
    _, tri_group = vertex_groups(src, joint_group)
    names = [im["name"] for im in images]
    hi = {"P": src.P, "N": src.N, "TAN": src.TAN, "UV": src.UV, "T": src.I, "group": tri_group,
          "maps": {n: np.asarray(images[i]["img"], np.float32) / 255.0 for i, n in enumerate(names)
                   if only is None or n in only},
          "normal_map": "normal"}
    lo = {"P": m["pos"], "N": m["nrm"], "TAN": m["tan"], "UV": m["uv"], "T": m["tris"], "group": m["group"]}
    maps, filled = mesh_bake.bake(hi, lo, atlas_px)
    print(f"baked {atlas_px} px atlas, {filled.mean() * 100:.0f}% of texels used")
    return {n: Image.fromarray(np.clip(v * 255.0 + 0.5, 0, 255).astype(np.uint8)) for n, v in maps.items()}


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
    out = {k: m[k][used] for k in ("pos", "nrm", "uv", "J", "W", "tan")}
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
    nrm = np.array(nrm)
    side = np.cross(nrm, np.where(np.abs(nrm[:, :1]) < 0.9, [[1.0, 0, 0]], [[0, 1.0, 0]]))
    tan = np.hstack([side / np.linalg.norm(side, axis=1, keepdims=True), np.ones((len(nrm), 1))])
    return {"pos": np.array(pos), "nrm": nrm, "uv": np.array(uv), "tan": tan,
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
        "TANGENT": W.acc(arr["tan"], 5126, "VEC4", target=34962),
        "TEXCOORD_0": W.acc(arr["uv"], 5126, "VEC2", target=34962),
        "JOINTS_0": W.acc(arr["J"], 5121, "VEC4", target=34962),
        "WEIGHTS_0": W.acc(wb, 5121, "VEC4", normalized=True, target=34962)},
        "indices": W.acc(tris.reshape(-1), 5125 if big_index else 5123, "SCALAR", target=34963),
        "material": material}


# ---------------------------------------------------------------- skeleton re-fit
# Each joint's new pivot: where the body part it moves meets its parent part
# ([parent part bone, child part bone]); bones that carry no geometry move
# with the joint named after "with:".
JOINT_FIT = {
    "Spine2": ("Hips", "Spine2"), "Spine1": "with:Spine2", "Spine": "with:Spine2",
    "Head": ("Spine2", "Head"), "Neck": "with:Head", "HeadTop_End": "with:Head", "headfront": "with:Head",
    "LeftArm": ("Spine2", "LeftArm"), "LeftShoulder": "with:LeftArm",
    "LeftForeArm": ("LeftArm", "LeftForeArm"), "LeftHand": "with:LeftForeArm", "LeftHandMiddle4": "with:LeftForeArm",
    "RightArm": ("Spine2", "RightArm"), "RightShoulder": "with:RightArm",
    "RightForeArm": ("RightArm", "RightForeArm"), "RightHand": "with:RightForeArm",
    "RightHandMiddle4": "with:RightForeArm",
    "LeftUpLeg": ("Hips", "LeftUpLeg"), "LeftLeg": ("LeftUpLeg", "LeftLeg"), "LeftFoot": ("LeftLeg", "LeftFoot"),
    "LeftToeBase": "with:LeftFoot", "LeftToe_End": "with:LeftFoot",
    "RightUpLeg": ("Hips", "RightUpLeg"), "RightLeg": ("RightUpLeg", "RightLeg"),
    "RightFoot": ("RightLeg", "RightFoot"), "RightToeBase": "with:RightFoot", "RightToe_End": "with:RightFoot",
}
# The game's cannon muzzles in hand space on the source rig (printed again
# for the re-fitted rig, for RobotSkirmisher.SKIRMISHER_MUZZLES).
MUZZLES_OLD = {"Left": np.array([0.0639, 0.2989, 0.0226]), "Right": np.array([-0.0098, 0.4991, 0.0349])}
# Vertices within this distance (m) of the closest contact count as contact.
CONTACT_BAND = 0.012


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_world(nodes, parent, i):
    def local(k):
        n = nodes[k]
        M = np.eye(4)
        M[:3, :3] = quat_mat(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]))
        M[:3, 3] = n.get("translation", [0, 0, 0])
        return M
    M = local(i)
    while i in parent:
        i = parent[i]
        M = local(i) @ M
    return M


def refit_skeleton(g, src):
    """Moves the joints into the mesh. The source's auto-rig put them up to
    a quarter metre off the parts they move (the hips in front of the
    pelvis, the spine at the chest plate, knees and hips off-centre), so
    every rigid part swung about the wrong point: the parts drifted apart
    as soon as a joint bent (worst with the game's aim twist). Each joint
    now sits where its part meets its parent part; joint orientations, the
    mesh and its skin weights are unchanged (the bind poses follow the new
    joints), and the clips keep their rotations. Updates g's nodes in place
    and returns [new inverse bind matrices, {node: global pivot shift}]."""
    from scipy.spatial import cKDTree
    nodes = g["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    skin = g["skins"][0]
    jname = {j: nodes[j]["name"].split(":")[-1] for j in skin["joints"]}
    by_name = {v: k for k, v in jname.items()}
    # Each welded vertex's (rigid) bone.
    dom = np.zeros(len(src.V), np.int64)
    for i, c in enumerate(src.copies):
        k = c[0]
        dom[i] = src.J[k, src.W[k].argmax()]
    part = {jname[j]: src.V[dom == k] for k, j in enumerate(skin["joints"])}
    old = {j: node_world(nodes, parent, j)[:3, 3] for j in skin["joints"]}
    new = dict(old)

    def contact(a, b):
        pa, pb = part[a], part[b]
        da, _ = cKDTree(pb).query(pa)
        db, _ = cKDTree(pa).query(pb)
        lim = min(da.min(), db.min()) + CONTACT_BAND
        return np.vstack([pa[da < lim], pb[db < lim]]).mean(0)
    for name, rule in JOINT_FIT.items():
        if isinstance(rule, tuple):
            new[by_name[name]] = contact(*rule)
    for name, rule in JOINT_FIT.items():
        if isinstance(rule, str):
            ref = by_name[rule[5:]]
            new[by_name[name]] = old[by_name[name]] + new[ref] - old[ref]
    # The hips: the middle of the two hip joints and the waist.
    hips = by_name["Hips"]
    new[hips] = np.mean([new[by_name["LeftUpLeg"]], new[by_name["RightUpLeg"]], new[by_name["Spine2"]]], 0)
    # New local translations (orientations unchanged, so only translations).
    world_rot = {j: node_world(nodes, parent, j)[:3, :3] for j in skin["joints"]}
    for j in skin["joints"]:
        pj = parent.get(j)
        if pj in new:
            local = world_rot[pj].T @ (new[j] - new[pj])
        else:
            M = node_world(nodes, parent, pj)[:3, :3] if pj is not None else np.eye(3)
            base = node_world(nodes, parent, pj)[:3, 3] if pj is not None else np.zeros(3)
            local = M.T @ (new[j] - base)
        nodes[j]["translation"] = [float(x) for x in local]
    ibm = []
    for j in skin["joints"]:
        ibm.append(np.linalg.inv(node_world(nodes, parent, j)).T.reshape(-1))
    shift = {j: new[j] - old[j] for j in skin["joints"]}
    print("joints moved (m): " + ", ".join(f"{jname[j]} {np.linalg.norm(shift[j]):.3f}" for j in skin["joints"]
                                           if isinstance(JOINT_FIT.get(jname[j]), tuple) or jname[j] == "Hips"))
    print(f"new hips rest {np.round(new[hips], 4).tolist()}")
    # Cannon muzzles (game constant, hand space) after the hands moved.
    for side, old_muzzle in MUZZLES_OLD.items():
        h = by_name[side + "Hand"]
        R = world_rot[h]
        print(f"muzzle {side}: {np.round(old_muzzle - R.T @ shift[h], 4).tolist()}")
    return np.array(ibm, np.float32), shift


def sample_quat(t_keys, q_keys, t):
    """Rotation track (linear, normalised) at times t."""
    out = np.empty((len(t), 4))
    for k in range(4):
        out[:, k] = np.interp(t, t_keys, q_keys[:, k])
    return out / np.linalg.norm(out, axis=1, keepdims=True)


def clip_pose(an, g, B, nodes, hips, hips_rot, hips_t, times):
    """Global 4x4 of every joint at each of `times` for clip `an` on the
    skeleton `nodes` (the hips with the given rotation/translation tracks,
    every other joint with the clip's rotations and its rest offset)."""
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    rot = {}
    for ch in an["channels"]:
        if ch["target"]["path"] == "rotation":
            smp = an["samplers"][ch["sampler"]]
            rot[ch["target"]["node"]] = sample_quat(read_acc(g, B, smp["input"])[:, 0],
                                                    read_acc(g, B, smp["output"]).astype(np.float64), times)
    rot[hips] = sample_quat(*hips_rot, times)
    tr_h = np.stack([np.interp(times, hips_t[0], hips_t[1][:, k]) for k in range(3)], 1)
    joints = g["skins"][0]["joints"]
    out = {}

    def world(j):
        if j in out:
            return out[j]
        n = nodes[j]
        M = np.tile(np.eye(4), (len(times), 1, 1))
        if j in rot:
            M[:, :3, :3] = np.stack([quat_mat(q) for q in rot[j]])
        else:
            M[:, :3, :3] = quat_mat(n.get("rotation", [0, 0, 0, 1]))
        M[:, :3, 3] = tr_h if j == hips else n.get("translation", [0, 0, 0])
        pj = parent.get(j)
        out[j] = M if pj not in joints else world(pj) @ M
        return out[j]
    for j in joints:
        world(j)
    return out


def lowest_point(pose, rest_inv, parts):
    """Height of the body's lowest point at each pose time."""
    low = None
    for j, pts in parts.items():
        X = pose[j] @ rest_inv[j]  # part transform
        y = (np.einsum("tij,pj->tpi", X[:, :3, :3], pts) + X[:, None, :3, 3])[:, :, 1].min(1)
        low = y if low is None else np.minimum(low, y)
    return low


def ground_offsets(an, g, B, old_nodes, hips, hips_rot, hips_old, hips_new, parts):
    """[times, dy]: how much to raise the re-fitted rig's hips so the body's
    lowest point follows the clip's (on the source rig) but never goes
    below the floor: the source clips sink the planted foot up to 15 cm
    into the floor (and the fallen body further), so this puts stance feet
    and fallen bodies exactly on the floor and keeps jumps and falls as high
    above it as in the clip. The clip's
    rotations stay as authored; with the joints in their right places the
    limbs reach a little differently, which this evens out too."""
    nodes = g["nodes"]
    times = None
    for ch in an["channels"]:
        if ch["target"]["path"] == "rotation":
            t = read_acc(g, B, an["samplers"][ch["sampler"]]["input"])[:, 0]
            times = t if times is None else np.union1d(times, t)
    times = np.union1d(times, hips_old[0])
    parent_old = {c: i for i, n in enumerate(old_nodes) for c in n.get("children", [])}
    parent_new = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    inv_old = {j: np.linalg.inv(node_world(old_nodes, parent_old, j)) for j in parts}
    inv_new = {j: np.linalg.inv(node_world(nodes, parent_new, j)) for j in parts}
    low_old = lowest_point(clip_pose(an, g, B, old_nodes, hips, hips_rot, hips_old, times), inv_old, parts)
    low_new = lowest_point(clip_pose(an, g, B, nodes, hips, hips_rot, hips_new, times), inv_new, parts)
    return times, np.maximum(low_old, 0.0) - low_new


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
    hips_node = next(n for n in g["nodes"] if n["name"] == "mixamorig:Hips")
    hips_rest_rot = quat_mat(hips_node.get("rotation", [0, 0, 0, 1]))
    old_hips_t = list(hips_node["translation"])
    old_nodes = json.loads(json.dumps(g["nodes"]))
    ibm, shift = refit_skeleton(g, src)
    skin = g["skins"][0]
    joint_names = [g["nodes"][j]["name"].split(":")[-1] for j in skin["joints"]]
    joint_section = np.array([SECTIONS.index(BONE_SECTION[n]) for n in joint_names])
    groups = sorted(set(BONE_GROUP.values()))
    joint_group = np.array([groups.index(BONE_GROUP[n]) for n in joint_names])

    # --- main model + baked textures
    srcimg = []
    for im in g["images"]:
        v = g["bufferViews"][im["bufferView"]]
        data = B[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        srcimg.append({"name": im["name"], "img": Image.open(io.BytesIO(data)).convert("RGB")})
    # SKIRMISHER_CACHE=<file>: reuse the meshes and bakes of an earlier run
    # (they don't depend on the skeleton or clips) - for iterating on those.
    cache_file = os.environ.get("SKIRMISHER_CACHE")
    if cache_file and os.path.exists(cache_file):
        import pickle
        m, baked, f, far_tex = pickle.load(open(cache_file, "rb"))
    else:
        m = lowpoly(src, TRIANGLES, joint_group, ATLAS_BAKE, ATLAS_PADDING)
        baked = bake_textures(src, m, srcimg, joint_group, ATLAS_BAKE)
        f = lowpoly(src, FAR_TRIANGLES, joint_group, FAR_ATLAS_BAKE, FAR_ATLAS_PADDING)
        far_tex = bake_textures(src, f, srcimg, joint_group, FAR_ATLAS_BAKE, ["texture_0"])["texture_0"]
        if cache_file:
            import pickle
            pickle.dump((m, baked, f, far_tex), open(cache_file, "wb"))
    images = []
    for im in g["images"]:
        size = TEXTURE_SIZE.get(im["name"], 1024)
        img = baked[im["name"]].resize((size, size), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=JPEG_QUALITY, subsampling=0)
        images.append({"name": im["name"], "mimeType": "image/jpeg", "data": out.getvalue()})
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
    motion_turns, motion_travel = {}, {}
    anims = []
    old_rest_t = old_hips_t
    # A sample of each part's vertices (bind space), for the re-grounding.
    rng = np.random.default_rng(1)
    dom = np.array([src.J[c[0], src.W[c[0]].argmax()] for c in src.copies])
    ground_parts = {}
    for k, j in enumerate(skin["joints"]):
        pts = src.V[dom == k]
        if len(pts):
            ground_parts[j] = pts[rng.choice(len(pts), min(len(pts), 300), replace=False)]
    ground_fix = {}
    for an in g["animations"]:
        na = {"name": an["name"], "samplers": [], "channels": []}
        name = an["name"]
        # The hips rotation as the clip will play it (yaw taken out of the
        # turn clips): moving the hips pivot needs it (see below).
        hips_rot = None
        for ch in an["channels"]:
            if ch["target"]["node"] == hips and ch["target"]["path"] == "rotation":
                smp = an["samplers"][ch["sampler"]]
                t = read_acc(g, B, smp["input"])[:, 0]
                q = read_acc(g, B, smp["output"]).astype(np.float64)
                if name in TURNS:
                    yaw = np.unwrap(2.0 * np.arctan2(q[:, 1], q[:, 3]))
                    c, s_ = np.cos(-yaw / 2), np.sin(-yaw / 2)
                    # q' = Ry(-yaw) * q
                    x, y, z, w = q.T
                    q2 = np.stack([c * x + s_ * z, c * y + s_ * w, c * z - s_ * x, c * w - s_ * y], 1)
                    motion_turns[name] = resample(t, (yaw - yaw[0]).reshape(-1, 1))
                else:
                    q2 = q
                hips_rot = (t, q2)
        # The hips track as the clip will play it, on the source rig (old)
        # and on the re-fitted one (new).
        hips_tr = None
        for ch in an["channels"]:
            if ch["target"]["node"] == hips and ch["target"]["path"] == "translation":
                smp = an["samplers"][ch["sampler"]]
                t = read_acc(g, B, smp["input"])[:, 0]
                vals = read_acc(g, B, smp["output"]).astype(np.float64)
                if name in TURNS or name in TRAVEL:
                    if name in TRAVEL:
                        motion_travel[name] = resample(t, vals[:, [0, 2]] - vals[0, [0, 2]])
                    # Hips stay over the body's centre, like the other clips.
                    vals[:, 0] = old_rest_t[0]
                    vals[:, 2] = old_rest_t[2]
                # New pivot: p' = p + R(t) R0^-1 shift, so the pelvis moves
                # exactly as before.
                q = sample_quat(*hips_rot, t)
                hips_tr = (t, vals, vals + np.stack([quat_mat(qq) @ hips_rest_rot.T @ shift[hips] for qq in q]))
        # Re-ground: the hips track on the clip's full time base, raised so
        # the body's lowest point matches the clip.
        gt, dy = ground_offsets(an, g, B, old_nodes, hips, hips_rot, (hips_tr[0], hips_tr[1]),
                                (hips_tr[0], hips_tr[2]), ground_parts)
        new_t = np.stack([np.interp(gt, hips_tr[0], hips_tr[2][:, k]) for k in range(3)], 1)
        new_t[:, 1] += dy
        hips_tr = (gt, hips_tr[1], new_t)
        ground_fix[name] = float(np.abs(dy).max())
        for ch in an["channels"]:
            smp = an["samplers"][ch["sampler"]]
            inp = keep(smp["input"])
            node = ch["target"]["node"]
            on_hips = node == hips
            path = ch["target"]["path"]
            if on_hips and path == "translation":
                inp = W.acc(hips_tr[0].reshape(-1, 1), 5126, "SCALAR", minmax=True)
                out = W.acc(hips_tr[2], 5126, "VEC3")
            elif on_hips and path == "rotation" and name in TURNS:
                out = W.acc(hips_rot[1], 5126, "VEC4")
            elif path == "translation":
                # Every other joint's track is its (constant) rest offset.
                n = g["accessors"][smp["output"]]["count"]
                out = W.acc(np.tile(np.array(g["nodes"][node]["translation"]), (n, 1)), 5126, "VEC3")
            else:
                out = keep(smp["output"])
            na["samplers"].append({"input": inp, "output": out, "interpolation": smp.get("interpolation", "LINEAR")})
            na["channels"].append({"sampler": len(na["samplers"]) - 1, "target": ch["target"]})
        anims.append(na)
    skins = [{"joints": skin["joints"], "inverseBindMatrices": W.acc(ibm, 5126, "MAT4"),
              **({"skeleton": skin["skeleton"]} if "skeleton" in skin else {})}]

    print("re-grounding (max hips shift per clip, m): "
          + ", ".join(f"{k} {v:.3f}" for k, v in ground_fix.items()))
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
          f"({m['locked']} locked); sections: " + ", ".join(stats))

    # --- far LOD: one mesh, no textures/clips.
    W = Writer()
    cache.clear()
    nodes = json.loads(json.dumps(g["nodes"]))
    nodes[mesh_node]["name"] = "Body"
    meshes = [{"name": "Body", "primitives": [primitive(W, f, f["tris"], 0)]}]
    skins = [{"joints": skin["joints"], "inverseBindMatrices": W.acc(ibm, 5126, "MAT4"),
              **({"skeleton": skin["skeleton"]} if "skeleton" in skin else {})}]
    out = io.BytesIO()
    far_tex.resize((FAR_TEXTURE_SIZE, FAR_TEXTURE_SIZE), Image.LANCZOS).save(out, "JPEG", quality=JPEG_QUALITY)
    mat = {"name": "FarMaterial", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                                           "metallicFactor": 0.6, "roughnessFactor": 0.5}}
    gl = {"asset": {"version": "2.0", "generator": "CONSTRUCT-ERROR tools/build_robot_skirmisher.py"},
          "scene": 0, "scenes": g["scenes"], "nodes": nodes, "meshes": meshes, "skins": skins,
          "materials": [mat], "textures": [{"sampler": 0, "source": 0}],
          "images": [{"name": "far", "mimeType": "image/jpeg", "bufferView": W.blob(out.getvalue())}],
          "samplers": g["samplers"]}
    total = W.save(OUT_FAR, gl)
    print(f"{os.path.relpath(OUT_FAR, ROOT)}: {total:,} bytes; {len(f['tris'])} triangles, {len(f['pos'])} vertices")


if __name__ == "__main__":
    main()
