#!/usr/bin/env python3
"""Straightens the grunts' forearm cannons (owner asked: "straighten it out so
it's linear like majority of the player's weapons as the weapons mesh is
bent"):

    python3 tools/straighten_grunt_cannons.py      (needs numpy, scipy)

  edits in place: assets/characters/robot/robot_enemy.glb
                  assets/characters/robot/robot_enemy_far.glb (its far LOD)
  (the originals are in git history before this tool's commit; the files are
  marked `asset.extras.cannons_straightened`, so running it again does
  nothing)

Each cannon (Left_ / Right_Forearm_Weapon, rigid on its forearm bone) runs
from the elbow joint ring through a long housing to the green muzzle. The
modelled cannon isn't straight: measured against the forearm (the line
from the elbow to the wrist, which the cannon is mounted along), the
housing is turned ~4 deg sideways and the muzzle ~10 deg, a bend that
builds up from the elbow to the tip. That's unbent here: every point is
carried round by the bend's angle at its distance along the forearm (0 at
the elbow ring, which stays exactly as it is - it's the joint - easing
into the housing's angle, then into the muzzle's), so housing and muzzle
line up along the forearm, one straight piece. Normals and tangents are
turned with it. The bend is measured on the full model (minimum-volume
boxes round the housing and the muzzle) and the same unbending applied to
the far LOD's simplified copy.

It also prints where the muzzles are now, in the hand bones' space - the
centres of the green tips the bolts fire from: RobotEnemy.MUZZLES (also
the sentinel's) takes them.
"""
import json, os, struct, sys
import numpy as np
from scipy.spatial import ConvexHull

ROOT = os.path.join(os.path.dirname(__file__), "..")
MAIN = os.path.join(ROOT, "assets/characters/robot/robot_enemy.glb")
FAR = os.path.join(ROOT, "assets/characters/robot/robot_enemy_far.glb")
# Along the forearm (m from the elbow joint): the joint ring stays put up to
# JOINT_END; the housing's angle is reached by HOUSING[0] and held to
# HOUSING[1]; the muzzle's is reached by MUZZLE[0].
JOINT_END = 0.06
HOUSING = (0.12, 0.38)
MUZZLE = (0.46,)
HOUSING_SPAN = (0.1, 0.42)
MUZZLE_SPAN = (0.42, 0.6)

COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", d[off:off + 4])[0]
    return js, bytearray(d[off + 8:off + 8 + bl])


def write_glb(path, js, buf):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((4 - len(j) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(buf)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(buf), 0x004E4942) + bytes(buf))


def _layout(js, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    dt = np.dtype(COMP[a["componentType"]])
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or n * dt.itemsize
    return a, n, dt, off, stride


def get(js, b, i):
    a, n, dt, off, stride = _layout(js, i)
    idx = np.arange(a["count"])[:, None] * stride + np.arange(n * dt.itemsize)[None, :] + off
    return np.frombuffer(bytes(b), np.uint8)[idx].copy().view(dt).reshape(a["count"], n)


def put(js, b, i, arr):
    a, n, dt, off, stride = _layout(js, i)
    raw = np.ascontiguousarray(arr.astype(dt)).view(np.uint8).reshape(a["count"], -1)
    mv = np.frombuffer(b, np.uint8)
    for k in range(a["count"]):
        mv[off + k * stride:off + k * stride + raw.shape[1]] = raw[k]
    if "min" in a:
        a["min"] = [float(x) for x in arr.min(0)]
        a["max"] = [float(x) for x in arr.max(0)]


def joints(js, b, node):
    sk = js["skins"][node["skin"]]
    ibm = get(js, b, sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    names = [js["nodes"][j].get("name") for j in sk["joints"]]
    return {n: ibm[k] for k, n in enumerate(names)}


def frame(ibm, side):
    """Elbow position and the forearm's frame (along, up, sideways)."""
    fa = np.linalg.inv(ibm["mixamorig:%sForeArm" % side])[:3, 3]
    hd = np.linalg.inv(ibm["mixamorig:%sHand" % side])[:3, 3]
    ax = (hd - fa) / np.linalg.norm(hd - fa)
    up = np.array([0.0, 1.0, 0.0]) - ax * ax[1]
    up /= np.linalg.norm(up)
    return fa, ax, up, np.cross(ax, up)


def box_axis(P, ax, up, sd):
    """The long axis of the smallest box round P (within 16 deg of the
    forearm), as (sideways, up) angles in degrees."""
    def vol(d):
        a = np.cross(d, up)
        a /= np.linalg.norm(a)
        c = np.cross(d, a)
        Q = np.stack([P @ a, P @ c], 1)
        h = Q[ConvexHull(Q).vertices]
        best = 9.0
        for th in np.radians(np.arange(0, 90, 1.0)):
            R = np.array([[np.cos(th), -np.sin(th)], [np.sin(th), np.cos(th)]])
            r = h @ R
            best = min(best, np.ptp(r[:, 0]) * np.ptp(r[:, 1]))
        return best * np.ptp(P @ d)
    best = (9.0, (0.0, 0.0))
    for yaw in np.arange(-16, 16.01, 0.5):
        for pit in np.arange(-16, 16.01, 0.5):
            y, p = np.radians(yaw), np.radians(pit)
            d = ax * np.cos(y) * np.cos(p) + sd * np.sin(y) * np.cos(p) + up * np.sin(p)
            v = vol(d)
            if v < best[0]:
                best = (v, (yaw, pit))
    return best[1]


def rot(axis, ang):
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K


class Unbend:
    """The bend's angles along one forearm, and the mapping that unbends it."""

    def __init__(self, fa, ax, up, sd, housing, muzzle):
        self.fa, self.ax, self.up, self.sd = fa, ax, up, sd
        self.knots = [(-1.0, (0.0, 0.0)), (JOINT_END, (0.0, 0.0)), (HOUSING[0], housing),
                      (HOUSING[1], housing), (MUZZLE[0], muzzle), (9.0, muzzle)]
        ts = np.linspace(JOINT_END, 0.8, 600)
        self._ts = ts
        dirs = np.array([self._dir(t) for t in ts])
        steps = np.diff(ts)[:, None] * (dirs[:-1] + dirs[1:]) * 0.5
        self._curve = np.vstack([[0, 0, 0], np.cumsum(steps, 0)])  # from the joint end

    def angles(self, t):
        ks = self.knots
        for (t0, a0), (t1, a1) in zip(ks[:-1], ks[1:]):
            if t <= t1:
                k = np.clip((t - t0) / (t1 - t0), 0.0, 1.0)
                k = k * k * (3 - 2 * k)
                return (a0[0] + (a1[0] - a0[0]) * k, a0[1] + (a1[1] - a0[1]) * k)
        return ks[-1][1]

    def _dir(self, t):
        y, p = np.radians(self.angles(t))
        return self.ax * np.cos(y) * np.cos(p) + self.sd * np.sin(y) * np.cos(p) + self.up * np.sin(p)

    def rotation(self, t):
        """Turns the bent direction at `t` back onto the forearm."""
        d = self._dir(t)
        c = np.cross(d, self.ax)
        s = np.linalg.norm(c)
        if s < 1e-9:
            return np.eye(3)
        return rot(c, np.arcsin(min(1.0, s)))

    def apply(self, P, N=None, T=None):
        P2 = P.copy()
        N2 = None if N is None else N.copy()
        T2 = None if T is None else T.copy()
        J = self.fa + self.ax * JOINT_END
        for i, p in enumerate(P):
            t = (p - self.fa) @ self.ax
            if t <= JOINT_END:
                continue
            R = self.rotation(t)
            k = min(int((t - JOINT_END) / (self._ts[1] - self._ts[0])), len(self._ts) - 1)
            on_bent = J + self._curve[k]
            on_straight = J + self.ax * (self._ts[k] - JOINT_END)
            P2[i] = on_straight + R @ (p - on_bent)
            if N2 is not None:
                N2[i] = R @ N[i]
            if T2 is not None:
                T2[i, :3] = R @ T[i, :3]
        return P2, N2, T2


def weapons(js):
    for n in js["nodes"]:
        name = n.get("name") or ""
        if "mesh" in n and name.endswith("_Forearm_Weapon"):
            yield name.split("_")[0], n


def main():
    js, b = read_glb(MAIN)
    if js["asset"].get("extras", {}).get("cannons_straightened"):
        print("already straightened")
        return
    fixes = {}
    for side, node in weapons(js):
        ibm = joints(js, b, node)
        fa, ax, up, sd = frame(ibm, side)
        p = js["meshes"][node["mesh"]]["primitives"][0]
        P = get(js, b, p["attributes"]["POSITION"])
        t = (P - fa) @ ax
        housing = box_axis(P[(t > HOUSING_SPAN[0]) & (t < HOUSING_SPAN[1])], ax, up, sd)
        muzzle = box_axis(P[(t > MUZZLE_SPAN[0]) & (t < MUZZLE_SPAN[1])], ax, up, sd)
        print("%s cannon: housing turned %.1f deg sideways, %.1f up; muzzle %.1f, %.1f" % (side, housing[0], housing[1], muzzle[0], muzzle[1]))
        fixes[side] = (housing, muzzle)
    for path in (MAIN, FAR):
        js, b = read_glb(path)
        if js["asset"].get("extras", {}).get("cannons_straightened"):
            continue
        for side, node in weapons(js):
            ibm = joints(js, b, node)
            fa, ax, up, sd = frame(ibm, side)
            u = Unbend(fa, ax, up, sd, *fixes[side])
            for p in js["meshes"][node["mesh"]]["primitives"]:
                at = p["attributes"]
                P = get(js, b, at["POSITION"])
                N = get(js, b, at["NORMAL"]) if "NORMAL" in at else None
                T = get(js, b, at["TANGENT"]) if "TANGENT" in at else None
                P2, N2, T2 = u.apply(P, N, T)
                put(js, b, at["POSITION"], P2)
                if N2 is not None:
                    put(js, b, at["NORMAL"], N2)
                if T2 is not None:
                    put(js, b, at["TANGENT"], T2)
                print("  %s %s: %d vertices, moved up to %.1f mm" % (os.path.basename(path), node["name"], len(P), np.abs(P2 - P).max() * 1000))
        js["asset"].setdefault("extras", {})["cannons_straightened"] = True
        write_glb(path, js, b)
    muzzles()


def muzzles():
    """The straightened muzzles: the centre of each cannon's last 3 cm, in
    its hand bone's space (`--muzzles` prints them again)."""
    js, b = read_glb(MAIN)
    for side, node in weapons(js):
        ibm = joints(js, b, node)
        fa, ax, up, sd = frame(ibm, side)
        P = get(js, b, js["meshes"][node["mesh"]]["primitives"][0]["attributes"]["POSITION"])
        t = (P - fa) @ ax
        tip = P[t > t.max() - 0.03]
        h = ibm["mixamorig:%sHand" % side] @ np.append((tip.min(0) + tip.max(0)) * 0.5, 1.0)
        print("%s muzzle (hand space): Vector3(%.3f, %.3f, %.3f)" % (side, h[0], h[1], h[2]))


if __name__ == "__main__":
    muzzles() if "--muzzles" in sys.argv else main()
