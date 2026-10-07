#!/usr/bin/env python3
"""Builds the game-ready robot boss from the untouched Meshy source:

    python3 tools/build_robot_boss.py [death_clip.json]

  in:  assets/enemies/robot_boss/robot_boss_source.glb   (never modified)
  out: assets/enemies/robot_boss/robot_boss.glb

The skeleton, skin weights, bind poses, body animation clips, the chaingun
rotor and its Chaingun_Fire_Loop clip and Missile_Spawn are copied as they
are. Changes (all reproducible from here):

  * Surfaces a previous tool mapped to one pure-black texel (UV 0.7019,
    0.0032; its normal-map value is badly tilted, and all three UVs of each
    triangle coincide, which leaves no tangent frame) render as black voids.
    They get tiny planar UVs inside uniform grey patches of the same atlas
    (the robot's own armour grey; darker metal on the chaingun bearings).
  * Chest: the slide-rail mesh is removed (its thin rails poked out of the
    torso), the plate-sized recess back wall is replaced by an armour
    bulkhead with a small core pocket, and a lightweight red emissive
    Reactor_Core (own material, own node) sits in that pocket. The four
    chest clips are replaced by a downward-hinging flap:
    Chest_Open / Chest_Close (motion) and Chest_Open_Hold / Chest_Closed
    (poses). Only the flap node is animated.
  * Optional: an authored death clip (from tools/author_boss_death.gd) is
    added.
  * Storage: tangents dropped (Godot regenerates them on import), weights
    stored as normalized bytes, textures stored as high-quality JPEG (the
    odd 2816 px metallic-roughness map resized to 2048), buffer repacked
    without unused data.
"""
import io
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets/enemies/robot_boss/robot_boss_source.glb")
OUT = os.path.join(ROOT, "assets/enemies/robot_boss/robot_boss.glb")

VOID_UV = np.array([0.7019043, 0.00317383], dtype=np.float32)
# Uniform, flat-normal patches of the atlas (13 px windows), rough non-metal.
GUNMETAL_DARK = (0.17504883, 0.65942383)   # albedo ~0.105 (core pocket inside)
GUNMETAL_LIGHT = (0.60864258, 0.62036133)  # albedo ~0.158 (chaingun bearings)
ARMOUR_GREY = (0.76538086, 0.80639648)     # albedo ~0.214 (the robot's grey armour)
RED_ARMOUR = (0.48706055, 0.68334961)      # the robot's red armour
# Visor: the face slit (bind-space box) - its red/pink texels get their own
# emissive red material.
VISOR_BOX = ((-0.3, 1.41, 0.06), (0.0, 1.50, 1.0))
VISOR_MIN_RED = 0.5

# Rocket arm: an armoured launcher housing around the old missile tube,
# built on the launch axis (Missile_Spawn's +Z), bind space.
LAUNCH_BASE = np.array([-0.7083123163, 0.9828118265, 0.2427060883])
LAUNCH_AXIS = np.array([-0.0781280614, 0.2864695583, 0.9548985277])
# Fitted to the forearm block (which runs about -0.4..0.4 m along the axis
# and reaches down into the fist), so the launcher IS the forearm.
HOUSING_Z = (-0.22, 0.43)     # rear / front along the axis
HOUSING_CENTRE = (-0.01, 0.0)  # cross-section centre (side, up) off the axis
HOUSING_HALF = (0.2, 0.19)    # half width (sideways) / height
HOUSING_CHAMFER = 0.065
HOUSING_REAR_SCALE = 0.8      # tapers into the elbow
PORT_RADIUS = 0.135           # wide missile silo (housing size unchanged)
PORT_DEPTH = 0.5
PORT_FRAME = 0.022            # red ring round the opening
NOZZLE_LIP = 0.035            # the ring stands this far proud of the face
# Missile_Spawn = where the loaded missile's centre sits: middle of the bore.
MISSILE_SPAWN_FORWARD = HOUSING_Z[1] - PORT_DEPTH * 0.5

# Chaingun muzzle: on the rotor's spin axis, at the barrel tips.
ROTOR_AXIS = np.array([-0.0200661844, 0.9543148349, 0.2981284935])
MUZZLE_ALONG = 0.285

# Chest (model/bind space, metres). The recess back wall is flat at z 0.015.
CHAMBER_BACK_Z = 0.015
CORE_CENTRE = np.array([-0.125, 1.077, -0.032])
POCKET_HALF = (0.075, 0.065)  # half width / height of the opening
POCKET_BACK_Z = -0.093
CORE_RADIUS = 0.052

# Flap hinge (in the flap's parent space): its front-bottom edge.
HINGE_PIVOT = np.array([-0.002, -0.239, -0.018])
OPEN_DEG = 172.0              # folds right down against the belly: core fully clear
UNLATCH = 0.03                # pops out this far before swinging


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
    return out.view(dt).reshape(a["count"], n)


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


# ---------------------------------------------------------------- maths
def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def axis_angle_quat(axis, ang):
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    s = math.sin(ang / 2)
    return np.array([axis[0] * s, axis[1] * s, axis[2] * s, math.cos(ang / 2)])


def node_globals(g):
    parent = {}
    for i, n in enumerate(g["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    G = {}

    def gm(i):
        if i in G:
            return G[i]
        n = g["nodes"][i]
        m = np.eye(4)
        m[:3, :3] = quat_mat(n.get("rotation", [0, 0, 0, 1])) @ np.diag(n.get("scale", [1, 1, 1]))
        m[:3, 3] = n.get("translation", [0, 0, 0])
        if i in parent:
            m = gm(parent[i]) @ m
        G[i] = m
        return m

    for i in range(len(g["nodes"])):
        gm(i)
    return G


def ease_in_out(t):
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- uv fix
MICRO_UV = 0.002  # UV units per metre: a few pixels inside the uniform patch


def micro_uv(pos, nor, centre):
    """Tiny planar UVs around `centre` instead of one point: triangles whose
    three UVs coincide get no valid tangent frame, so normal mapping makes
    them render black."""
    pos = np.asarray(pos, float)
    dom = np.abs(nor).argmax(1)
    other = np.array([[1, 2], [0, 2], [0, 1]])[dom]
    a = pos[np.arange(len(pos)), other[:, 0]]
    b = pos[np.arange(len(pos)), other[:, 1]]
    uv = np.stack([centre[0] + (a - a.mean()) * MICRO_UV, centre[1] + (b - b.mean()) * MICRO_UV], 1)
    return uv.astype(np.float32)


# ---------------------------------------------------------------- geometry
def clip_poly(poly, axis, value, keep_greater):
    """Sutherland-Hodgman clip of a convex polygon (list of 2D points)."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        pin = (p[axis] >= value) if keep_greater else (p[axis] <= value)
        qin = (q[axis] >= value) if keep_greater else (q[axis] <= value)
        if pin:
            out.append(p)
        if pin != qin:
            t = (value - p[axis]) / (q[axis] - p[axis])
            out.append(p + (q - p) * t)
    return out


def chest_housing(back_tris):
    """The recess back wall (its own outline, `back_tris` = (n,3,2) xy at
    CHAMBER_BACK_Z) with the core opening cut out, plus the small core
    pocket behind it. Bind space."""
    cx, cy = CORE_CENTRE[0], CORE_CENTRE[1]
    hx, hy = POCKET_HALF
    hx0, hx1, hy0, hy1 = cx - hx, cx + hx, cy - hy, cy + hy
    z = CHAMBER_BACK_Z
    pos, nor, uvc, idx = [], [], [], []

    def poly(points3, n, uv):
        if len(points3) < 3:
            return
        base = len(pos)
        for p in points3:
            pos.append(p)
            nor.append(n)
            uvc.append(uv)
        for i in range(1, len(points3) - 1):
            idx.extend([base, base + i, base + i + 1])

    # Back wall minus the opening: left / right strips, then above / below.
    for t in back_tris:
        tri = [np.array(p, float) for p in t]
        pieces = [clip_poly(tri, 0, hx0, False), clip_poly(tri, 0, hx1, True)]
        mid = clip_poly(clip_poly(tri, 0, hx0, True), 0, hx1, False)
        if mid:
            pieces += [clip_poly(mid, 1, hy0, False), clip_poly(mid, 1, hy1, True)]
        for pc in pieces:
            poly([(p[0], p[1], z) for p in pc], (0, 0, 1), ARMOUR_GREY)
    zb = POCKET_BACK_Z
    P = lambda x, y, zz: (x, y, zz)
    poly([P(hx0, hy0, zb), P(hx1, hy0, zb), P(hx1, hy0, z), P(hx0, hy0, z)], (0, 1, 0), GUNMETAL_DARK)
    poly([P(hx0, hy1, z), P(hx1, hy1, z), P(hx1, hy1, zb), P(hx0, hy1, zb)], (0, -1, 0), GUNMETAL_DARK)
    poly([P(hx0, hy0, z), P(hx0, hy1, z), P(hx0, hy1, zb), P(hx0, hy0, zb)], (1, 0, 0), GUNMETAL_DARK)
    poly([P(hx1, hy0, zb), P(hx1, hy1, zb), P(hx1, hy1, z), P(hx1, hy0, z)], (-1, 0, 0), GUNMETAL_DARK)
    poly([P(hx0, hy0, zb), P(hx0, hy1, zb), P(hx1, hy1, zb), P(hx1, hy0, zb)], (0, 0, 1), GUNMETAL_DARK)
    pos = np.array(pos, float)
    nor = np.array(nor, float)
    tris = np.array(idx).reshape(-1, 3)
    # Counter-clockwise around each normal (glTF front faces).
    for t in tris:
        a, b, c = pos[t]
        if np.dot(np.cross(b - a, c - a), nor[t[0]]) < 0:
            t[1], t[2] = t[2], t[1]
    # Tiny planar UVs per part (valid tangents), around each part's texel.
    uv = np.zeros((len(pos), 2), np.float32)
    for centre in (ARMOUR_GREY, GUNMETAL_DARK):
        sel = np.array([u == centre for u in uvc])
        if sel.any():
            uv[sel] = micro_uv(pos[sel], nor[sel], centre)
    return pos, nor, uv, tris.reshape(-1)


def icosphere(r, subdiv=1):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                m = v[a] + v[b]
                v.append(m / np.linalg.norm(m))
                cache[k] = len(v) - 1
            return cache[k]

        nf = []
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    P = np.array(v)
    return P * r, P.copy(), np.array(f).reshape(-1)


_BASE_CACHE = {}


def sample_base(g, B, uv):
    """Base-colour texel (0..1 RGB) at each UV of the source atlas."""
    if "img" not in _BASE_CACHE:
        ti = g["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        im = g["images"][g["textures"][ti]["source"]]
        v = g["bufferViews"][im["bufferView"]]
        data = B[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        _BASE_CACHE["img"] = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), np.float32) / 255.0
    img = _BASE_CACHE["img"]
    h, w = img.shape[:2]
    x = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
    y = np.clip((uv[:, 1] * h).astype(int), 0, h - 1)
    return img[y, x]


# ---------------------------------------------------------------- rocket arm
def launch_frame():
    a = LAUNCH_AXIS / np.linalg.norm(LAUNCH_AXIS)
    up = np.array([0.0, 1.0, 0.0])
    u = up - a * up.dot(a)
    u /= np.linalg.norm(u)
    side = np.cross(u, a)  # +side = the robot's left (inwards for the right arm)
    return a, u, side


def octagon(hw, hh, ch):
    return [(-hw + ch, hh), (hw - ch, hh), (hw, hh - ch), (hw, -hh + ch),
            (hw - ch, -hh), (-hw + ch, -hh), (-hw, -hh + ch), (-hw, hh - ch)]


def launcher_housing():
    """Faceted armour housing (bind space): chamfered octagonal shell along
    the launch axis tapering into the forearm, dark launch port at the
    front, red armour plates on top and outside and a red front collar."""
    a, u, sd = launch_frame()
    pos, nor, uvc, idx = [], [], [], []

    cx, cy = HOUSING_CENTRE

    def P(x, y, z):
        return LAUNCH_BASE + sd * x + u * y + a * z

    def C(points):
        return [(x + cx, y + cy) for x, y in points]

    def face(points, uv, out_hint=None):
        pts = [np.asarray(p, float) for p in points]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        if np.linalg.norm(n) < 1e-9:
            return
        n /= np.linalg.norm(n)
        if out_hint is not None and n.dot(out_hint) < 0:
            pts = pts[::-1]
            n = -n
        base = len(pos)
        for p in pts:
            pos.append(p)
            nor.append(n)
            uvc.append(uv)
        for i in range(1, len(pts) - 1):
            idx.extend([base, base + i, base + i + 1])

    def prism(oct_a, za, oct_b, zb, uv, centre_xy=(0.0, 0.0)):
        # side quads between two octagons, normals pointing away from the axis
        for i in range(8):
            j = (i + 1) % 8
            q = [P(*oct_a[i], za), P(*oct_a[j], za), P(*oct_b[j], zb), P(*oct_b[i], zb)]
            mid = (np.array(oct_a[i]) + np.array(oct_a[j])) / 2 - np.array(centre_xy)
            face(q, uv, sd * mid[0] + u * mid[1])

    hw, hh = HOUSING_HALF
    ch = HOUSING_CHAMFER
    z0, z1 = HOUSING_Z
    front = C(octagon(hw, hh, ch))
    rear = C([(x * HOUSING_REAR_SCALE, y * HOUSING_REAR_SCALE) for x, y in octagon(hw, hh, ch)])
    zm = z0 + 0.16
    prism(rear, z0, front, zm, ARMOUR_GREY, (cx, cy))
    prism(front, zm, front, z1, ARMOUR_GREY, (cx, cy))
    face([P(*p, z0) for p in rear], ARMOUR_GREY, -a)
    # Front face: a wide round silo opening. 16 points round the front
    # octagon (its corners and edge midpoints), the round port / its red
    # nozzle ring at the same angles, so the ring of quads between them
    # closes exactly.
    ring_xy = []
    for i in range(8):
        j = (i + 1) % 8
        ring_xy.append(front[i])
        ring_xy.append(((front[i][0] + front[j][0]) / 2, (front[i][1] + front[j][1]) / 2))
    angs = [math.atan2(y, x) for x, y in ring_xy]
    port = [(PORT_RADIUS * math.cos(t), PORT_RADIUS * math.sin(t)) for t in angs]
    frame = [((PORT_RADIUS + PORT_FRAME) * math.cos(t), (PORT_RADIUS + PORT_FRAME) * math.sin(t)) for t in angs]
    n16 = len(ring_xy)
    zl = z1 + NOZZLE_LIP
    for i in range(n16):
        j = (i + 1) % n16
        face([P(*ring_xy[i], z1), P(*ring_xy[j], z1), P(*frame[j], z1), P(*frame[i], z1)], ARMOUR_GREY, a)
        mid = (np.array(frame[i]) + np.array(frame[j])) / 2
        out = sd * mid[0] + u * mid[1]
        # nozzle ring: outer wall, front annulus
        face([P(*frame[i], z1 - 0.01), P(*frame[j], z1 - 0.01), P(*frame[j], zl), P(*frame[i], zl)], GUNMETAL_LIGHT, out)
        face([P(*frame[i], zl), P(*frame[j], zl), P(*port[j], zl), P(*port[i], zl)], RED_ARMOUR, a)
        # bore wall (dark) from the lip back to the bottom, two lighter
        # guide rings inside
        face([P(*port[i], zl), P(*port[j], zl), P(*port[j], z1 - PORT_DEPTH), P(*port[i], z1 - PORT_DEPTH)], GUNMETAL_DARK, -out)
        for zr in (z1 - 0.12, z1 - 0.3):
            pin = [(x * 0.94, y * 0.94) for x, y in (port[i], port[j])]
            face([P(*port[i], zr), P(*port[j], zr), P(*pin[1], zr), P(*pin[0], zr)], GUNMETAL_LIGHT, a)
            face([P(*pin[0], zr), P(*pin[1], zr), P(*pin[1], zr - 0.02), P(*pin[0], zr - 0.02)], GUNMETAL_LIGHT, -out)
            face([P(*port[i], zr - 0.02), P(*port[j], zr - 0.02), P(*pin[1], zr - 0.02), P(*pin[0], zr - 0.02)], GUNMETAL_LIGHT, -a)
    face([P(*p, z1 - PORT_DEPTH) for p in port], GUNMETAL_DARK, a)
    # Red front collar (slightly proud of the shell).
    col_o = C([(x * 1.08, y * 1.08) for x, y in octagon(hw, hh, ch)])
    cz0, cz1 = z1 - 0.1, z1 - 0.015
    prism(col_o, cz0, col_o, cz1, RED_ARMOUR, (cx, cy))
    for i in range(8):
        j = (i + 1) % 8
        face([P(*front[i], cz1), P(*front[j], cz1), P(*col_o[j], cz1), P(*col_o[i], cz1)], RED_ARMOUR, a)
        face([P(*front[i], cz0), P(*front[j], cz0), P(*col_o[j], cz0), P(*col_o[i], cz0)], RED_ARMOUR, -a)

    def plate(x0, x1, y0, y1, za, zb, outward, col=RED_ARMOUR):
        # a box plate on the shell: corners (x, y) across, za..zb along
        c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        for i in range(4):
            j = (i + 1) % 4
            mid = (np.array(c[i]) + np.array(c[j])) / 2 - np.array([(x0 + x1) / 2, (y0 + y1) / 2])
            face([P(*c[i], za), P(*c[j], za), P(*c[j], zb), P(*c[i], zb)], col, sd * mid[0] + u * mid[1])
        face([P(*p, zb) for p in c], col, a)
        face([P(*p, za) for p in c], col, -a)

    plate(cx - 0.11, cx + 0.11, cy + hh - 0.01, cy + hh + 0.03, 0.0, 0.24, u)            # top
    plate(cx - hw - 0.03, cx - hw + 0.01, cy - 0.1, cy + 0.08, -0.02, 0.26, -sd, ARMOUR_GREY)  # outer side

    def panel(x, y0, y1, za, zb, n, uv):
        # thin inset panel / slot lying on a side face (x = const)
        face([P(x, y0, za), P(x, y1, za), P(x, y1, zb), P(x, y0, zb)], uv, n)

    def top_slot(x0, x1, za, zb, uv):
        y = cy + hh + 0.031
        face([P(x0, y, za), P(x1, y, za), P(x1, y, zb), P(x0, y, zb)], uv, u)

    panel(cx + hw + 0.006, cy - 0.12, cy + 0.1, -0.06, 0.3, sd, GUNMETAL_LIGHT)         # inner side
    panel(cx - hw - 0.031, cy - 0.06, cy + 0.04, 0.02, 0.22, -sd, GUNMETAL_LIGHT)       # on the red side plate
    for k in range(3):                                                                  # vents on the top plate
        top_slot(cx - 0.07, cx + 0.07, 0.03 + k * 0.07, 0.06 + k * 0.07, GUNMETAL_DARK)
    pos = np.array(pos, float)
    nor = np.array(nor, float)
    uv = np.zeros((len(pos), 2), np.float32)
    for centre in (ARMOUR_GREY, RED_ARMOUR, GUNMETAL_DARK, GUNMETAL_LIGHT):
        sel = np.array([c == centre for c in uvc])
        if sel.any():
            uv[sel] = micro_uv(pos[sel], nor[sel], centre)
    return pos, nor, uv, np.array(idx, np.uint32)


def inside_housing(p, margin=0.012):
    """Points (bind space) inside the launcher housing (shrunk by margin)."""
    a, u, sd = launch_frame()
    d = p - LAUNCH_BASE
    x, y, z = d @ sd, d @ u, d @ a
    hw, hh = HOUSING_HALF
    z0, z1 = HOUSING_Z
    x = x - HOUSING_CENTRE[0]
    y = y - HOUSING_CENTRE[1]
    k = np.clip((z - z0) / 0.16, 0.0, 1.0)
    sc = HOUSING_REAR_SCALE + (1.0 - HOUSING_REAR_SCALE) * k
    inside = (z > z0 + margin) & (z < z1 - margin)
    inside &= (np.abs(x) < hw * sc - margin) & (np.abs(y) < hh * sc - margin)
    inside &= (np.abs(x) + np.abs(y) < (hw + hh - HOUSING_CHAMFER) * sc - margin)
    # (the old launch tube's bore included: the silo is the housing's own)
    return inside


# ---------------------------------------------------------------- chest clips
def chest_pose(theta, slide, axis):
    q = axis_angle_quat(axis, theta)
    R = quat_mat(q)
    t = HINGE_PIVOT - R @ HINGE_PIVOT + np.array([0, 0, slide])
    return q, t


def chest_clip(name, keys, axis):
    """keys: list of (time, theta_deg, slide)."""
    times, rots, trans = [], [], []
    for t, th, sl in keys:
        q, tr = chest_pose(math.radians(th), sl, axis)
        times.append(t)
        rots.append(q)
        trans.append(tr)
    return name, np.array(times), np.array(rots), np.array(trans)


def open_keys():
    keys = []
    # Unlatch: pop out 2 cm.
    for i in range(5):
        u = i / 4
        keys.append((0.06 * u, 0.0, UNLATCH * ease_in_out(u)))
    # Swing down (accelerating, like a heavy hatch), overshoot a little ...
    n = 18
    for i in range(1, n + 1):
        u = i / n
        keys.append((0.06 + 0.26 * u, (OPEN_DEG + 4.0) * u * u, UNLATCH))
    # ... and settle on its stop.
    for i in range(1, 7):
        u = i / 6
        keys.append((0.32 + 0.13 * u, OPEN_DEG + 4.0 * math.cos(u * math.pi * 1.5) * (1 - u), UNLATCH))
    keys[-1] = (0.45, OPEN_DEG, UNLATCH)
    return keys


def close_keys():
    keys = []
    n = 18
    for i in range(n + 1):
        u = i / n
        keys.append((0.30 * u, OPEN_DEG * (1 - ease_in_out(u)), UNLATCH))
    for i in range(1, 5):
        u = i / 4
        keys.append((0.30 + 0.08 * u, 0.0, UNLATCH * (1 - ease_in_out(u))))
    return keys


# ---------------------------------------------------------------- build
def main():
    # Authored clips (tools/author_boss_*.gd write these).
    import glob
    clip_paths = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "tools/robot_boss_*.json")))
    g, B = load(SRC)
    names = {n["name"]: i for i, n in enumerate(g["nodes"])}
    G = node_globals(g)
    W = Writer()
    cache = {}

    def keep(i, target=None):
        if i not in cache:
            a = g["accessors"][i]
            data = read_acc(g, B, i)
            cache[i] = W.acc(data, a["componentType"], a["type"], a.get("normalized", False), target,
                             "min" in a)
        return cache[i]

    out_meshes = []
    mesh_map = {}
    removed_tris = 0
    housing_hidden = 0
    visor_tris = 0
    visor_prim = None
    remapped = 0
    back_xy = np.zeros((0, 3, 2))
    for mi, m in enumerate(g["meshes"]):
        if m["name"] == "Chest_Plate_Carriage":
            continue  # slide rails: removed
        pr = m["primitives"][0]
        at = pr["attributes"]
        uv = read_acc(g, B, at["TEXCOORD_0"]).astype(np.float32)
        void = np.all(np.abs(uv - VOID_UV) < 2e-4, axis=1)
        remapped += int(void.sum())
        if void.any():
            centre = GUNMETAL_LIGHT if m["name"] == "Chaingun_Barrel_Rotor" else ARMOUR_GREY
            uv[void] = micro_uv(read_acc(g, B, at["POSITION"])[void], read_acc(g, B, at["NORMAL"])[void], centre)
        idx = read_acc(g, B, pr["indices"]).reshape(-1, 3).astype(np.uint32)
        if m["name"] == "Robot_Body":
            P = read_acc(g, B, at["POSITION"])
            Nn = read_acc(g, B, at["NORMAL"])
            orig_void = np.all(np.abs(read_acc(g, B, at["TEXCOORD_0"]) - VOID_UV) < 2e-4, axis=1)
            c = P[idx].mean(1)
            fn = np.cross(P[idx[:, 1]] - P[idx[:, 0]], P[idx[:, 2]] - P[idx[:, 0]])
            fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
            back = (orig_void[idx].all(1) & (np.abs(c[:, 2] - CHAMBER_BACK_Z) < 0.002) & (np.abs(fn[:, 2]) > 0.9)
                    & (c[:, 0] > -0.40) & (c[:, 0] < 0.15) & (c[:, 1] > 0.94) & (c[:, 1] < 1.21))
            removed_tris = int(back.sum())
            facing = back & (fn[:, 2] > 0.9)
            back_xy = P[idx[facing]][:, :, :2]
            idx = idx[~back]
            # Old tube surfaces now enclosed by the launcher housing.
            hidden = inside_housing(P)[idx].all(1)
            housing_hidden = int(hidden.sum())
            idx = idx[~hidden]
        prim = {"attributes": {}, "material": pr.get("material", 0)}
        prim["attributes"]["POSITION"] = keep(at["POSITION"], 34962)
        prim["attributes"]["NORMAL"] = keep(at["NORMAL"], 34962)
        prim["attributes"]["TEXCOORD_0"] = W.acc(uv, 5126, "VEC2", target=34962)
        if "JOINTS_0" in at:
            prim["attributes"]["JOINTS_0"] = keep(at["JOINTS_0"], 34962)
            w = read_acc(g, B, at["WEIGHTS_0"]).astype(np.float64)
            w /= w.sum(1, keepdims=True)
            wb = np.floor(w * 255 + 0.5).astype(np.int32)
            # Exact sum of 255 per vertex: fix the rounding on the largest weight.
            fix = 255 - wb.sum(1)
            wb[np.arange(len(wb)), w.argmax(1)] += fix
            prim["attributes"]["WEIGHTS_0"] = W.acc(wb.astype(np.uint8), 5121, "VEC4", normalized=True, target=34962)
        prims = [prim]
        if m["name"] == "Robot_Body":
            # Visor slit: its own (red emissive) primitive, same vertices.
            P = read_acc(g, B, at["POSITION"])
            c = P[idx].mean(1)
            col = sample_base(g, B, uv[idx].mean(1))
            lo, hi = np.array(VISOR_BOX[0]), np.array(VISOR_BOX[1])
            vis = np.all((c > lo) & (c < hi), axis=1) & (col[:, 0] > VISOR_MIN_RED)
            visor_tris = int(vis.sum())
            visor_prim = {"attributes": prim["attributes"], "material": None,
                          "indices": W.acc(idx[vis].reshape(-1), 5125, "SCALAR", target=34963)}
            idx = idx[~vis]
            prims.append(visor_prim)
        prim["indices"] = W.acc(idx.reshape(-1), 5125, "SCALAR", target=34963)
        mesh_map[mi] = len(out_meshes)
        out_meshes.append({"name": m["name"], "primitives": prims})

    nodes = json.loads(json.dumps(g["nodes"]))
    for n in nodes:
        if "mesh" in n:
            if n["mesh"] in mesh_map:
                n["mesh"] = mesh_map[n["mesh"]]
            else:
                del n["mesh"]

    spine2 = names["mixamorig:Spine2"]
    inv_sp = np.linalg.inv(G[spine2])

    def to_spine(p):
        p = np.asarray(p, float)
        return (inv_sp[:3, :3] @ p.T).T + inv_sp[:3, 3]

    def nrm_spine(nv):
        nv = (inv_sp[:3, :3] @ np.asarray(nv, float).T).T
        return nv / np.linalg.norm(nv, axis=1, keepdims=True)

    # Chest housing (bulkhead + pocket), body material.
    hp, hn, huv, hi = chest_housing(back_xy)
    housing_mesh = {"name": "Chest_Core_Housing", "primitives": [{"attributes": {
        "POSITION": W.acc(to_spine(hp), 5126, "VEC3", target=34962, minmax=True),
        "NORMAL": W.acc(nrm_spine(hn), 5126, "VEC3", target=34962),
        "TEXCOORD_0": W.acc(huv, 5126, "VEC2", target=34962)},
        "indices": W.acc(hi.astype(np.uint32), 5125, "SCALAR", target=34963), "material": 0}]}
    out_meshes.append(housing_mesh)
    nodes.append({"name": "Chest_Core_Housing", "mesh": len(out_meshes) - 1})
    nodes[spine2].setdefault("children", []).append(len(nodes) - 1)

    # Reactor core: its own emissive material, in its socket (moved into the pocket).
    materials = json.loads(json.dumps(g["materials"]))
    materials.append({"name": "Reactor_Core_Emissive",
                      "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.02, 0.01, 1.0],
                                               "metallicFactor": 0.0, "roughnessFactor": 0.35},
                      "emissiveFactor": [1.0, 0.03, 0.01],
                      "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 1.0}}})
    # Visor: strong red glow (the slit's own texture tinted red, emissive).
    base_tex = g["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]
    materials.append({"name": "Visor_Emissive",
                      "pbrMetallicRoughness": {"baseColorTexture": dict(base_tex), "baseColorFactor": [1.0, 0.15, 0.12, 1.0],
                                               "metallicFactor": 0.0, "roughnessFactor": 0.4},
                      "emissiveTexture": dict(base_tex), "emissiveFactor": [1.0, 0.1, 0.06],
                      "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 2.5}}})
    visor_prim["material"] = len(materials) - 1
    cp, cn, ci = icosphere(CORE_RADIUS, 1)
    core_mesh = {"name": "Reactor_Core", "primitives": [{"attributes": {
        "POSITION": W.acc(cp, 5126, "VEC3", target=34962, minmax=True),
        "NORMAL": W.acc(cn, 5126, "VEC3", target=34962)},
        "indices": W.acc(ci.astype(np.uint16), 5123, "SCALAR", target=34963), "material": len(materials) - 1}]}
    out_meshes.append(core_mesh)
    sock = names["Reactor_Core_Socket"]
    nodes[sock]["translation"] = [float(x) for x in to_spine(CORE_CENTRE)]
    nodes[sock].pop("rotation", None)
    nodes[sock]["extras"] = {"core": "Reactor_Core (separate node and material, for hit detection / glow)"}
    nodes.append({"name": "Reactor_Core", "mesh": len(out_meshes) - 1})
    nodes[sock].setdefault("children", []).append(len(nodes) - 1)
    # Rocket arm housing, rigid on the right forearm (body material).
    rfa = names["mixamorig:RightForeArm"]
    inv_rf = np.linalg.inv(G[rfa])
    lp, ln, luv, li = launcher_housing()
    lp_local = (inv_rf[:3, :3] @ lp.T).T + inv_rf[:3, 3]
    ln_local = (inv_rf[:3, :3] @ ln.T).T
    ln_local /= np.linalg.norm(ln_local, axis=1, keepdims=True)
    out_meshes.append({"name": "Rocket_Launcher_Housing", "primitives": [{"attributes": {
        "POSITION": W.acc(lp_local, 5126, "VEC3", target=34962, minmax=True),
        "NORMAL": W.acc(ln_local, 5126, "VEC3", target=34962),
        "TEXCOORD_0": W.acc(luv, 5126, "VEC2", target=34962)},
        "indices": W.acc(li, 5125, "SCALAR", target=34963), "material": 0}]})
    nodes.append({"name": "Rocket_Launcher_Housing", "mesh": len(out_meshes) - 1})
    nodes[rfa].setdefault("children", []).append(len(nodes) - 1)

    # Missile_Spawn: same node and orientation, moved forward along its +Z
    # into the launch port's bore (the missile appears in the bore and
    # leaves through the port).
    ms = nodes[names["Missile_Spawn"]]
    ms_r = quat_mat(ms["rotation"])
    ms["translation"] = [float(x) for x in np.array(ms["translation"]) + ms_r @ np.array([0.0, 0.0, MISSILE_SPAWN_FORWARD])]
    ms["extras"] = dict(ms.get("extras", {}), note="in the launcher housing's bore; +Z out through the port")

    # Chaingun muzzle: +Z along the barrel axis, at the barrel tips.
    lfa = names["mixamorig:LeftForeArm"]
    rotor_n = g["nodes"][names["Chaingun_Barrel_Rotor"]]
    ax = ROTOR_AXIS / np.linalg.norm(ROTOR_AXIS)
    rq = axis_angle_quat(np.cross([0.0, 0.0, 1.0], ax), math.acos(np.clip(ax[2], -1, 1)))
    nodes.append({"name": "Chaingun_Muzzle",
                  "translation": [float(x) for x in np.array(rotor_n["translation"]) + ax * MUZZLE_ALONG],
                  "rotation": [float(x) for x in rq],
                  "extras": {"forward_axis": "+Z", "note": "chaingun firing point: barrel tips, along the spin axis"}})
    nodes[lfa].setdefault("children", []).append(len(nodes) - 1)

    nodes[names["Chest_Plate_Carriage"]]["extras"] = {"note": "parent of the hinged flap (slide rails removed)"}
    flap = names["Chest_Frown_Plate_Hinge"]
    axis = np.array(g["nodes"][flap]["extras"]["hinge_axis_local"], float)
    nodes[flap]["extras"] = {"closed_by_default": True, "hinge": "front-bottom edge, opens downward",
                             "hinge_pivot_parent_space": [float(x) for x in HINGE_PIVOT],
                             "hinge_axis_parent_space": [float(x) for x in axis / np.linalg.norm(axis)],
                             "open_degrees": OPEN_DEG}

    # Animations: originals except the old chest clips, plus the new ones.
    anims = []
    for a in g["animations"]:
        if a["name"].startswith("Chest_"):
            continue
        na = {"name": a["name"], "channels": [], "samplers": []}
        for s in a["samplers"]:
            na["samplers"].append({"input": keep(s["input"]), "output": keep(s["output"]),
                                   "interpolation": s.get("interpolation", "LINEAR")})
        for c in a["channels"]:
            na["channels"].append({"sampler": c["sampler"], "target": dict(c["target"])})
        anims.append(na)
    clips = [
        chest_clip("Chest_Open", open_keys(), axis),
        chest_clip("Chest_Close", close_keys(), axis),
        chest_clip("Chest_Open_Hold", [(0.0, OPEN_DEG, UNLATCH), (0.1, OPEN_DEG, UNLATCH)], axis),
        chest_clip("Chest_Closed", [(0.0, 0.0, 0.0), (0.1, 0.0, 0.0)], axis),
    ]
    for name, times, rots, trans in clips:
        ti = W.acc(times.reshape(-1, 1), 5126, "SCALAR", minmax=True)
        anims.append({"name": name, "samplers": [
            {"input": ti, "output": W.acc(rots, 5126, "VEC4"), "interpolation": "LINEAR"},
            {"input": ti, "output": W.acc(trans, 5126, "VEC3"), "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": flap, "path": "rotation"}},
                         {"sampler": 1, "target": {"node": flap, "path": "translation"}}]})
    for clip_path in clip_paths:
        data = json.load(open(clip_path))
        for dc in data.get("clips", [data]):
            na = {"name": dc["name"], "samplers": [], "channels": []}
            for tr in dc["tracks"]:
                ti = W.acc(np.array(tr["times"], float).reshape(-1, 1), 5126, "SCALAR", minmax=True)
                vals = np.array(tr["values"], float)
                na["samplers"].append({"input": ti, "output": W.acc(vals, 5126, "VEC4" if vals.shape[1] == 4 else "VEC3"),
                                       "interpolation": "LINEAR"})
                na["channels"].append({"sampler": len(na["samplers"]) - 1,
                                       "target": {"node": names[tr["node"]], "path": tr["path"]}})
            anims.append(na)

    # Skin.
    skins = json.loads(json.dumps(g["skins"]))
    for s in skins:
        s["inverseBindMatrices"] = keep(s["inverseBindMatrices"])

    # Textures: high-quality JPEG (4:4:4), 2048 px.
    images = []
    for im in g["images"]:
        v = g["bufferViews"][im["bufferView"]]
        data = B[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        img = Image.open(io.BytesIO(data)).convert("RGB")
        if img.size != (2048, 2048):
            img = img.resize((2048, 2048), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=95 if im["name"] == "normal" else 93, subsampling=0, optimize=True)
        images.append({"name": im["name"], "mimeType": "image/jpeg", "bufferView": W.blob(out.getvalue())})

    gl = {"asset": {"version": "2.0", "generator": "CONSTRUCT-ERROR tools/build_robot_boss.py"},
          "extensionsUsed": ["KHR_materials_emissive_strength"],
          "scene": 0, "scenes": g["scenes"], "nodes": nodes, "meshes": out_meshes, "skins": skins,
          "animations": anims, "materials": materials, "textures": g["textures"], "images": images,
          "samplers": g["samplers"], "accessors": W.accessors, "bufferViews": W.views,
          "buffers": [{"byteLength": len(W.buf)}]}
    js = json.dumps(gl, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(W.buf) % 4:
        W.buf.append(0)
    total = 12 + 8 + len(js) + 8 + len(W.buf)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(W.buf), 0x004E4942) + bytes(W.buf))
    print(f"{OUT}: {total:,} bytes (source {os.path.getsize(SRC):,}); "
          f"{remapped} void-texel vertices remapped, {removed_tris} recess-back triangles replaced, "
          f"{housing_hidden} enclosed tube triangles removed, {visor_tris} visor triangles, "
          f"{len(anims)} clips")


if __name__ == "__main__":
    main()
