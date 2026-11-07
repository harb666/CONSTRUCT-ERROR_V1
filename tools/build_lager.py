"""Builds the playable Lager model from the owner's upload.

    python3 tools/build_lager.py
    (needs numpy, scipy, Pillow and gltfpack on PATH or GLTFPACK)

Source: assets/characters/lager/source/lager_source.glb (the owner's
Waffle_Warrior_Optimized.glb, untouched, not imported: .gdignore).
Output: assets/characters/lager/lager.glb.

She comes rigged (the same 32-bone rig as Harbinger's upload) with five
clips: Running, Walking, RunFast and two run turns. Nothing about her look is
changed; she is already the others' size (1.7 m, hips 0.82 m - Harbinger's
0.81 m), so she is not rescaled.

1. Arms: her forearms end in big waffle gauntlets with a glowing lens. The
   auto-rig weighted their front half 30-80 % to the hand bones, so any wrist
   movement bent the armour like rubber. Everything weighted to a hand (and
   its finger bones) now follows the forearm: each gauntlet is one rigid
   piece, and the weapons plug in at its lens end (CharacterAnimator
   arm_end_offset, measured below).
2. Hair: the long hair hanging down her back moved as one block with the
   head and back. It gets its own chain of bones (Hair_Root -> Hair_1 ->
   Hair_2 -> Hair_End, hanging from the head) and the hanging hair is
   weighted along it (blending into the head at the scalp, and softly into
   the body where its inner edge is welded to the back); the game swings
   the chain with a spring simulation (scripts/character/hair_springs.gd).
   The hair is found by colour (white / cream with gold streaks) behind the
   back below the head (the mesh is one welded piece).
3. Animations: her own Running, Walking and RunFast are kept. The other
   clips the game uses (Idle 9, jumps, falls, turns, slide, death, climb)
   are retargeted from Harbinger's (the same motion library, already named
   for the game, with her Fall2): each bone copies the source bone's
   world-space rotation relative to its bind pose, after lining up the two
   rigs' bind-pose bone directions; the hips' movement is scaled by hip
   height. Then, as for Harbinger, a constant tilt on each Foot bone
   levels her soles in the idle, applied to the retargeted clips.
4. Meshes simplified with gltfpack (-si 0.6, as the others), the animation
   data copied back byte for byte (tools/transplant_animations.py).
"""
import io, json, os, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from build_harbinger import (read_glb, write_glb, accessor, Writer, qmul, qmat, mat_q,
                             sample, Rig, sole_normal, clip_mesh)

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets/characters/lager/source/lager_source.glb")
REF = os.path.join(ROOT, "assets/characters/harbinger/harbinger.glb")
OUT = os.path.join(ROOT, "assets/characters/lager/lager.glb")

KEEP = ["Running", "Walking", "RunFast"]
RETARGET = ["Idle 9", "Idle Turn Left", "Idle Turn Right", "Regular Jump", "Run Sharp Turn Right",
            "slide right", "Dead", "Climb Attempt and Fall 5", "Fall1", "Fall2"]
MIX = "mixamorig:"
# Bone -> the child its direction is measured to (bind pose). Bones not
# listed use their parent's alignment (hands follow the forearm, feet the
# shin: both rigs have flat soles in the bind pose, so the feet copy the
# source's sole orientation, not its ankle-to-toe line).
DIR_CHILD = {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
             "Head": "HeadTop_End"}
for s in ("Left", "Right"):
    DIR_CHILD.update({s + "Shoulder": s + "Arm", s + "Arm": s + "ForeArm", s + "ForeArm": s + "Hand",
                      s + "UpLeg": s + "Leg", s + "Leg": s + "Foot"})
# Arm ends: distance (m) from each forearm joint along the forearm where the
# waffle gauntlet ends and the built-in cannon (dark ring, gold barrel,
# glowing lens) begins (measured from the texture colours along the arm).
CUT = {"Left": float(os.environ.get("CUT_L", 0.318)), "Right": float(os.environ.get("CUT_R", 0.358))}
HAND_BONES = {"Left": ["mixamorig:LeftHand", "Bone_029", "Bone_020", "Bone_019"],
              "Right": ["mixamorig:RightHand", "Bone_030", "Bone_025", "Bone_024"]}

# Hair: hanging part = below HAIR_TOP, behind HAIR_Z (bind pose, m).
HAIR_TOP, HAIR_Z = 1.32, -0.245
# Hair chain joints (heights, m): root, 1, 2, end. Each bone's weight peaks
# at its middle; the head's at HAIR_HEAD and above.
HAIR_Y = [1.27, 1.12, 0.97, 0.80]
HAIR_HEAD = 1.30
HAIR_NAMES = ["Hair_Root", "Hair_1", "Hair_2", "Hair_End"]


def minimal_arc(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.999999:
        ax = np.cross(a, [1.0, 0, 0])
        if np.linalg.norm(ax) < 1e-6:
            ax = np.cross(a, [0, 1.0, 0])
        ax /= np.linalg.norm(ax)
        return rotm(ax, np.pi)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx / (1 + c)


def rotm(axis, ang):
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K


def ortho(m):
    u, _, vt = np.linalg.svd(m)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


class Model:
    """A skinned GLB: nodes by name, parents, bind (= rest) world transforms, clips."""

    def __init__(self, path):
        self.js, self.b = read_glb(path)
        js = self.js
        self.idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
        self.parent = {}
        for i, n in enumerate(js["nodes"]):
            for c in n.get("children", []):
                self.parent[c] = i
        skin = js["skins"][0]
        self.joints = skin["joints"]
        ibm = accessor(js, self.b, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
        self.ibm = ibm
        self.bind = {self.joints[i]: np.linalg.inv(ibm[i]) for i in range(len(self.joints))}
        self.anims = {}
        for a in js.get("animations", []):
            ch = {}
            for c in a["channels"]:
                s = a["samplers"][c["sampler"]]
                ch[(c["target"]["node"], c["target"]["path"])] = (
                    accessor(js, self.b, s["input"])[:, 0].astype(np.float64),
                    accessor(js, self.b, s["output"]).astype(np.float64))
            self.anims[a["name"]] = ch
        self.rig = Rig(js, self.anims)

    def bind_of(self, name):
        return self.bind[self.idx[name]]


def retarget(src, dst, clip):
    """`clip` of `src` on `dst`'s rig: {(node, path): (times, values)}."""
    bones = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]
    for s in ("Left", "Right"):
        bones += [s + "Shoulder", s + "Arm", s + "ForeArm", s + "Hand"]
    for s in ("Left", "Right"):
        bones += [s + "UpLeg", s + "Leg", s + "Foot", s + "ToeBase", s + "Toe_End"]
    # World alignment of each bone's bind direction (dst -> src).
    align = {}
    for bn in bones:
        k = bn
        while k not in DIR_CHILD:
            pn = dst.js["nodes"][dst.parent[dst.idx[MIX + k]]]["name"]
            k = pn[len(MIX):]
        c = DIR_CHILD[k]
        ds = src.bind_of(MIX + c)[:3, 3] - src.bind_of(MIX + k)[:3, 3]
        dd = dst.bind_of(MIX + c)[:3, 3] - dst.bind_of(MIX + k)[:3, 3]
        align[bn] = minimal_arc(dd, ds)
    times = sorted({float(t) for (tin, _) in src.anims[clip].values() for t in tin})
    times = np.array(times)
    hip_k = dst.bind_of(MIX + "Hips")[1, 3] / src.bind_of(MIX + "Hips")[1, 3]
    rot = {bn: [] for bn in bones}
    hips_t = []
    for t in times:
        G = src.rig.globals(clip, t)
        Gt = {}
        for bn in bones:
            si, di = src.idx[MIX + bn], dst.idx[MIX + bn]
            Bs = ortho(src.bind[si][:3, :3])
            Bt = ortho(dst.bind[di][:3, :3])
            Gt[bn] = ortho(G[si][:3, :3]) @ Bs.T @ align[bn] @ Bt
        for bn in bones:
            di = dst.idx[MIX + bn]
            pi = dst.parent.get(di)
            pname = dst.js["nodes"][pi]["name"] if pi is not None else ""
            if pname.startswith(MIX) and pname[len(MIX):] in Gt:
                local = Gt[pname[len(MIX):]].T @ Gt[bn]
            else:
                local = Gt[bn]  # under the identity armature root
            rot[bn].append(mat_q(local))
        sp = G[src.idx[MIX + "Hips"]][:3, 3] - src.bind_of(MIX + "Hips")[:3, 3]
        hips_t.append(dst.bind_of(MIX + "Hips")[:3, 3] + sp * hip_k)
    out = {}
    for bn in bones:
        q = np.array(rot[bn])
        for i in range(1, len(q)):  # keep the quaternions on one hemisphere
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
        out[(dst.idx[MIX + bn], "rotation")] = (times, q)
    out[(dst.idx[MIX + "Hips"], "translation")] = (times, np.array(hips_t))
    return out


def base_colours(js, b, UV):
    from PIL import Image
    tex = js["textures"][js["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
    bv = js["bufferViews"][js["images"][tex]["bufferView"]]
    raw = b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
    img = np.asarray(Image.open(io.BytesIO(raw)).convert("RGB")).astype(np.float64) / 255.0
    h, w, _ = img.shape
    px = np.clip((UV[:, 0] % 1.0) * w, 0, w - 1).astype(int)
    py = np.clip((UV[:, 1] % 1.0) * h, 0, h - 1).astype(int)
    return img[py, px]


def hair_mask(P, I, C):
    """The hanging hair: below the head, behind the back, mostly white."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    _, inv = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    inv = inv.ravel()
    n = inv.max() + 1
    mx, mn = C.max(1), C.min(1)
    white = (mx > 0.72) & ((mx - mn) / np.maximum(mx, 1e-6) < 0.25)
    cand = (P[:, 1] < HAIR_TOP) & (P[:, 2] < HAIR_Z)
    T = inv[I[cand[I].all(1)]]
    r = np.r_[T[:, 0], T[:, 1], T[:, 2]]
    c = np.r_[T[:, 1], T[:, 2], T[:, 0]]
    _, lab = connected_components(coo_matrix((np.ones(len(r)), (r, c)), shape=(n, n)), directed=False)
    vlab = lab[inv]
    hair = np.zeros(len(P), bool)
    for k in np.unique(vlab[cand]):
        m = cand & (vlab == k)
        if m.sum() >= 30 and white[m].mean() > 0.3:
            hair |= m
    # Soft edge: spread a few rings into the neighbouring (welded) mesh
    # behind the back, so the hair's inner edge doesn't tear when it swings.
    h = hair.astype(np.float64)
    hp = np.zeros(n)
    np.maximum.at(hp, inv, h)
    T2 = inv[I]
    a = np.r_[T2[:, 0], T2[:, 1], T2[:, 2], T2[:, 1], T2[:, 2], T2[:, 0]]
    bb = np.r_[T2[:, 1], T2[:, 2], T2[:, 0], T2[:, 0], T2[:, 1], T2[:, 2]]
    P_u = np.zeros((n, 3))
    P_u[inv] = P
    free = (P_u[:, 1] < HAIR_TOP) & (P_u[:, 2] < -0.17)
    for _ in range(4):
        s = np.zeros(n)
        cnt = np.zeros(n)
        np.add.at(s, a, hp[bb])
        np.add.at(cnt, a, 1.0)
        avg = s / np.maximum(cnt, 1)
        hp = np.where(free, np.maximum(hp, avg * 0.75), hp)
    return hp[inv], hair


def hair_bones(P, hair):
    """World joint positions of the hair chain (on the hair's middle)."""
    pts = []
    for y in HAIR_Y:
        m = hair & (np.abs(P[:, 1] - y) < 0.03)
        if m.sum() < 10:
            m = hair & (np.abs(P[:, 1] - y) < 0.08)
        z = 0.5 * (P[m, 2].min() + P[m, 2].max())
        pts.append(np.array([0.0, y, z]))
    return pts


def hair_weights(y):
    """[(bone, weight)] along the chain for a vertex at height y (head = 'Head')."""
    mids = [0.5 * (HAIR_Y[i] + HAIR_Y[i + 1]) for i in range(3)]
    knots = [(HAIR_HEAD, "Head")] + [(mids[i], HAIR_NAMES[i]) for i in range(3)]
    if y >= knots[0][0]:
        return [("Head", 1.0)]
    for (y0, b0), (y1, b1) in zip(knots, knots[1:]):
        if y >= y1:
            f = (y0 - y) / (y0 - y1)
            return [(b0, 1.0 - f), (b1, f)]
    return [(HAIR_NAMES[2], 1.0)]


def basis_y(d):
    """Rotation whose +Y points along d (X kept near world X)."""
    yv = d / np.linalg.norm(d)
    xv = np.array([1.0, 0, 0]) - yv * yv[0]
    xv /= np.linalg.norm(xv)
    zv = np.cross(xv, yv)
    return np.stack([xv, yv, zv], 1)


def build_prep():
    dst = Model(SRC)
    src = Model(REF)
    js, b = dst.js, dst.b
    skin = js["skins"][0]
    joints = list(skin["joints"])
    jname = [js["nodes"][k]["name"] for k in joints]
    jindex = {n: i for i, n in enumerate(jname)}
    prim = js["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    P = accessor(js, b, at["POSITION"]).astype(np.float64)
    N = accessor(js, b, at["NORMAL"]).astype(np.float64)
    UV = accessor(js, b, at["TEXCOORD_0"]).astype(np.float64)
    J = accessor(js, b, at["JOINTS_0"]).astype(np.int64)
    W = accessor(js, b, at["WEIGHTS_0"]).astype(np.float64)
    I = accessor(js, b, prim["indices"]).reshape(-1, 3).astype(np.int64)

    # 1. Arm ends: the built-in cannons cut off at the end of the waffle
    # gauntlets (crossing triangles clipped exactly, so the rim is clean);
    # tools/build_mesh_caps.gd seals the openings into stumps.
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        fa = dst.bind_of(MIX + side + "ForeArm")[:3, 3]
        hd = dst.bind_of(MIX + side + "Hand")[:3, 3]
        ax = (hd - fa) / np.linalg.norm(hd - fa)
        d = (P - fa) @ ax
        rad = np.linalg.norm(P - fa - np.outer(d, ax), axis=1)
        region = (P[:, 0] * sx > 0.4) & (d > 0.2) & (rad < 0.25)
        P, N, UV, J, W, I, removed = clip_mesh(P, N, UV, J, W, I, d - CUT[side], region)
        print("%s arm end: cannon cut %.3f m past the elbow, %d triangles removed/clipped" % (side, CUT[side], removed))
    used = np.zeros(len(P), bool)
    used[I.ravel()] = True
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(used.sum())
    P, N, UV, J, W = P[used], N[used], UV[used], J[used], W[used]
    I = remap[I]

    # 1b. Rigid gauntlets.
    for side, names in HAND_BONES.items():
        fa = jindex[MIX + side + "ForeArm"]
        ids = [jindex[n] for n in names]
        moved = np.isin(J, ids) & (W > 0)
        J[moved] = fa
        print("%s arm: %d vertices' hand weights moved to the forearm" % (side, int(moved.any(1).sum())))

    # 2. Hair chain.
    C = base_colours(js, b, UV)
    hfield, hair = hair_mask(P, I, C)
    pts = hair_bones(P, hair)
    print("hair: %d vertices (%d blended at the edge); joints %s" % (
        hair.sum(), int(((hfield > 0.01) & ~hair).sum()), [np.round(p, 3).tolist() for p in pts]))
    head_node = dst.idx[MIX + "Head"]
    head_bind = dst.bind[head_node]
    binds = []
    for i in range(4):
        d = (pts[i + 1] - pts[i]) if i < 3 else (pts[3] - pts[2])
        M = np.eye(4)
        M[:3, :3] = basis_y(d)
        M[:3, 3] = pts[i]
        binds.append(M)
    parent_bind = head_bind
    parent_node = head_node
    new_idx = []
    for i, nm in enumerate(HAIR_NAMES):
        L = np.linalg.inv(parent_bind) @ binds[i]
        node = {"name": nm, "translation": L[:3, 3].tolist(), "rotation": mat_q(ortho(L[:3, :3])).tolist()}
        js["nodes"].append(node)
        ni = len(js["nodes"]) - 1
        js["nodes"][parent_node].setdefault("children", []).append(ni)
        joints.append(ni)
        jindex[nm] = len(joints) - 1
        new_idx.append(ni)
        parent_bind, parent_node = binds[i], ni
    skin["joints"] = joints
    ibm = np.concatenate([dst.ibm, np.array([np.linalg.inv(m) for m in binds])])
    # Weights: hair verts follow the chain, blended with their own by hfield.
    jid = {"Head": jindex[MIX + "Head"]}
    jid.update({n: jindex[n] for n in HAIR_NAMES})
    newJ, newW = J.copy(), W.copy()
    for v in np.where(hfield > 0.01)[0]:
        acc = {}
        for k in range(4):
            if W[v, k] > 0:
                acc[J[v, k]] = acc.get(J[v, k], 0.0) + W[v, k] * (1.0 - hfield[v])
        for bn, w in hair_weights(P[v, 1]):
            acc[jid[bn]] = acc.get(jid[bn], 0.0) + w * hfield[v]
        top = sorted(acc.items(), key=lambda t: -t[1])[:4]
        s = sum(w for _, w in top)
        newJ[v] = 0
        newW[v] = 0
        for k, (j, w) in enumerate(top):
            newJ[v, k] = j
            newW[v, k] = w / s
    J, W = newJ, newW
    # Merge duplicate joints per vertex (the gauntlet step can repeat one).
    for v in np.where((J[:, :, None] == J[:, None, :]).sum((1, 2)) > 4)[0]:
        acc = {}
        for k in range(4):
            if W[v, k] > 0:
                acc[J[v, k]] = acc.get(J[v, k], 0.0) + W[v, k]
        J[v] = 0
        W[v] = 0
        for k, (j, w) in enumerate(sorted(acc.items(), key=lambda t: -t[1])):
            J[v, k] = j
            W[v, k] = w

    # 3. Animations.
    clips = {n: dst.anims[n] for n in KEEP}
    rclips = {n: retarget(src, dst, n) for n in RETARGET}
    # Soles level in the (retargeted) idle.
    rig = Rig(js, dict(dst.anims, **rclips))
    dom = J[np.arange(len(J)), W.argmax(1)]
    corr = {}
    for side in ("Left", "Right"):
        foot = dst.idx[MIX + side + "Foot"]
        ids = [jindex[MIX + side + n] for n in ("Foot", "ToeBase", "Toe_End")]
        sole = np.isin(dom, ids) & (P[:, 1] < 0.015)
        sk_j = joints[:len(dst.joints)]
        normals = [sole_normal(rig, sk_j, dst.ibm, P, J, W, sole, "Idle 9", t) for t in (0.0, 0.5, 1.0, 1.5)]
        n0 = np.mean(normals, 0)
        n0 /= np.linalg.norm(n0)
        axis = np.cross(n0, [0.0, 1.0, 0.0])
        ang = np.arcsin(min(1.0, np.linalg.norm(axis)))
        if ang < 1e-4:
            continue
        axis /= np.linalg.norm(axis)
        G = rig.globals("Idle 9", 0.0)[foot][:3, :3]
        Gq = mat_q(ortho(G))
        Gi = Gq * np.array([-1, -1, -1, 1.0])
        world = np.r_[axis * np.sin(ang / 2), np.cos(ang / 2)]
        corr[foot] = qmul(qmul(Gi, world), Gq)
        after = sole_normal(rig, sk_j, dst.ibm, P, J, W, sole, "Idle 9", 0.0, {foot: corr[foot]})
        print("%s foot: soles %.1f deg off level in the idle -> %.1f deg" % (
            side, np.degrees(ang), np.degrees(np.arccos(min(1.0, after[1])))))
        for name in ("Running", "Walking"):
            tin = clips[name][(foot, "rotation")][0]
            nn = [sole_normal(rig, sk_j, dst.ibm, P, J, W, sole, name, t)[1] for t in tin[::4]]
            print("   (her own %s: soles at most %.1f deg off level)" % (name, np.degrees(np.arccos(min(1.0, max(nn))))))
    for ch in rclips.values():
        for (node, path), (tin, out) in list(ch.items()):
            if path == "rotation" and node in corr:
                ch[(node, path)] = (tin, qmul(out, corr[node][None, :]))
    clips.update(rclips)

    # Arm end: forearm joint -> the lens face, along the forearm.
    for side in ("Left", "Right"):
        fa = dst.bind_of(MIX + side + "ForeArm")[:3, 3]
        hd = dst.bind_of(MIX + side + "Hand")[:3, 3]
        ax = (hd - fa) / np.linalg.norm(hd - fa)
        m = (J[np.arange(len(J)), W.argmax(1)] == jindex[MIX + side + "ForeArm"])
        d = (P[m] - fa) @ ax
        print("%s gauntlet: lens face %.3f m past the elbow (forearm %.3f m)" % (side, d.max(), np.linalg.norm(hd - fa)))

    # Write.
    w = Writer()
    for img in js["images"]:
        bv = js["bufferViews"][img["bufferView"]]
        img["bufferView"] = w.view(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    skin["inverseBindMatrices"] = w.acc(ibm.transpose(0, 2, 1).reshape(-1, 16).astype(np.float32), "MAT4")
    prim["attributes"] = {
        "POSITION": w.acc(P.astype(np.float32), "VEC3", True, 34962),
        "NORMAL": w.acc((N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)).astype(np.float32), "VEC3", target=34962),
        "TEXCOORD_0": w.acc(UV.astype(np.float32), "VEC2", target=34962),
        "JOINTS_0": w.acc(J.astype(np.uint16), "VEC4", target=34962),
        "WEIGHTS_0": w.acc((W / W.sum(1, keepdims=True)).astype(np.float32), "VEC4", target=34962),
    }
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
