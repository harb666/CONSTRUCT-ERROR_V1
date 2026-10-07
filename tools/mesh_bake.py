"""Low-poly + texture re-bake helpers (used by build_robot_skirmisher.py).

    numpy, scipy, Pillow, meshoptimizer, xatlas

The flow: reduce the welded high-poly freely (positions only, bone-group
borders locked), unwrap the result with xatlas, then for every texel of the
new atlas find the matching point on the high-poly surface and copy its
base colour, metal/roughness and shading normal (the high-poly's vertex
normal bent by its normal map, re-expressed in the low-poly's tangent
frame). The low-poly then shades like the high-poly on far fewer triangles.
"""
import ctypes

import numpy as np
from scipy.ndimage import distance_transform_edt
from scipy.spatial import cKDTree


# ---------------------------------------------------------------- meshoptimizer
def _lib():
    from meshoptimizer._loader import lib
    c = ctypes
    f = lib.meshopt_simplifyWithAttributes
    f.restype = c.c_size_t
    f.argtypes = [c.POINTER(c.c_uint), c.POINTER(c.c_uint), c.c_size_t, c.POINTER(c.c_float), c.c_size_t,
                  c.c_size_t, c.POINTER(c.c_float), c.c_size_t, c.POINTER(c.c_float), c.c_size_t,
                  c.POINTER(c.c_ubyte), c.c_size_t, c.c_float, c.c_uint, c.POINTER(c.c_float)]
    return f


def simplify(tris, pos, attrs, weights, lock, target_tris, target_error=1.0):
    """meshopt_simplifyWithAttributes (the python package doesn't declare its
    argument types, so it is called directly). Returns the kept triangles."""
    c = ctypes
    idx = np.ascontiguousarray(tris.reshape(-1), np.uint32)
    P = np.ascontiguousarray(pos, np.float32)
    A = np.ascontiguousarray(attrs, np.float32)
    Wt = np.ascontiguousarray(weights, np.float32)
    L = np.ascontiguousarray(lock, np.uint8)
    dest = np.zeros(len(idx), np.uint32)
    err = c.c_float(0.0)
    n = _lib()(dest.ctypes.data_as(c.POINTER(c.c_uint)), idx.ctypes.data_as(c.POINTER(c.c_uint)), len(idx),
               P.ctypes.data_as(c.POINTER(c.c_float)), len(P), 12,
               A.ctypes.data_as(c.POINTER(c.c_float)), A.shape[1] * 4,
               Wt.ctypes.data_as(c.POINTER(c.c_float)), len(Wt),
               L.ctypes.data_as(c.POINTER(c.c_ubyte)), int(target_tris) * 3, target_error, 0, c.byref(err))
    return dest[:n].reshape(-1, 3).astype(np.int64)


# ---------------------------------------------------------------- geometry
def face_normals(P, T):
    n = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12), ln[:, 0] * 0.5


def crease_split(P, T, crease_deg):
    """Per-corner vertex ids + normals with hard edges above `crease_deg`:
    each corner's normal averages the faces round its vertex that lie within
    the crease angle of its own face (area-weighted)."""
    fn, area = face_normals(P, T)
    cos = np.cos(np.radians(crease_deg))
    corner_n = np.zeros((len(T), 3, 3))
    vf = [[] for _ in range(len(P))]
    for t, tri in enumerate(T):
        for k in range(3):
            vf[tri[k]].append(t)
    for t, tri in enumerate(T):
        for k in range(3):
            fs = np.array(vf[tri[k]])
            ok = fs[(fn[fs] @ fn[t]) >= cos]
            n = (fn[ok] * area[ok, None]).sum(0)
            corner_n[t, k] = n / max(np.linalg.norm(n), 1e-12)
    # Corners of the same vertex with (nearly) the same normal share a vertex.
    key = np.hstack([T.reshape(-1, 1), np.round(corner_n.reshape(-1, 3) * 1000)]).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    return T.reshape(-1)[first], corner_n.reshape(-1, 3)[first], inv.reshape(-1, 3)


def tangents(P, N, UV, T):
    """Per-vertex tangents (xyz + handedness w) from the UV layout."""
    p0, p1, p2 = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    u0, u1, u2 = UV[T[:, 0]], UV[T[:, 1]], UV[T[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = u1 - u0, u2 - u0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    t = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    b = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    tan = np.zeros_like(P)
    bit = np.zeros_like(P)
    for k in range(3):
        np.add.at(tan, T[:, k], t)
        np.add.at(bit, T[:, k], b)
    tan -= N * (tan * N).sum(1, keepdims=True)
    ln = np.linalg.norm(tan, axis=1, keepdims=True)
    # Degenerate: any vector perpendicular to the normal.
    alt = np.cross(N, np.where(np.abs(N[:, :1]) < 0.9, [[1.0, 0, 0]], [[0, 1.0, 0]]))
    tan = np.where(ln > 1e-12, tan / np.maximum(ln, 1e-12), alt / np.linalg.norm(alt, axis=1, keepdims=True))
    w = np.where((np.cross(N, tan) * bit).sum(1) < 0.0, -1.0, 1.0)
    return np.hstack([tan, w[:, None]])


def unwrap(P, N, T, resolution, padding):
    """xatlas: [vertex -> input vertex, triangles, uvs (0..1)]."""
    import xatlas
    atlas = xatlas.Atlas()
    atlas.add_mesh(P.astype(np.float32), T.astype(np.uint32), N.astype(np.float32))
    co = xatlas.ChartOptions()
    co.normal_seam_weight = 4.0
    co.max_iterations = 4
    po = xatlas.PackOptions()
    po.resolution = resolution
    po.padding = padding
    po.bilinear = True
    po.bruteForce = True
    po.rotate_charts = True
    atlas.generate(co, po)
    vmap, idx, uv = atlas[0]
    return vmap.astype(np.int64), idx.astype(np.int64), uv.astype(np.float64)


# ---------------------------------------------------------------- baking
def closest_on_triangles(p, a, b, c):
    """Closest point (as barycentrics) on triangles abc to points p (all (n, 3))."""
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = (ab * ap).sum(1), (ac * ap).sum(1)
    bp = p - b
    d3, d4 = (ab * bp).sum(1), (ac * bp).sum(1)
    cp = p - c
    d5, d6 = (ab * cp).sum(1), (ac * cp).sum(1)
    va = d3 * d6 - d5 * d4
    vb = d5 * d2 - d1 * d6
    vc = d1 * d4 - d3 * d2
    n = len(p)
    bary = np.zeros((n, 3))
    done = np.zeros(n, bool)

    def put(mask, u, v, w):
        m = mask & ~done
        bary[m] = np.stack([u, v, w], 1)[m]
        done[m] = True
    one, zero = np.ones(n), np.zeros(n)
    put((d1 <= 0) & (d2 <= 0), one, zero, zero)
    put((d3 >= 0) & (d4 <= d3), zero, one, zero)
    with np.errstate(divide="ignore", invalid="ignore"):
        v = d1 / (d1 - d3)
        put((vc <= 0) & (d1 >= 0) & (d3 <= 0), 1 - v, v, zero)
        put((d6 >= 0) & (d5 <= d6), zero, zero, one)
        w = d2 / (d2 - d6)
        put((vb <= 0) & (d2 >= 0) & (d6 <= 0), 1 - w, zero, w)
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        put((va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0), zero, 1 - w, w)
        den = 1.0 / (va + vb + vc)
        v, w = vb * den, vc * den
        put(np.ones(n, bool), 1 - v - w, v, w)
    return np.nan_to_num(bary, nan=1.0 / 3.0)


def rasterize(UV, T, size):
    """Texels covered by each triangle (a little beyond its edges, so the
    chart borders are filled too): [texel x, texel y, triangle, barycentrics]."""
    xs, ys, ts, bs = [], [], [], []
    pix = UV * size - 0.5
    for t in range(len(T)):
        q = pix[T[t]]
        x0, y0 = np.floor(q.min(0) - 1).astype(int)
        x1, y1 = np.ceil(q.max(0) + 1).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        gx, gy = gx.ravel(), gy.ravel()
        v0, v1 = q[1] - q[0], q[2] - q[0]
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(den) < 1e-12:
            continue
        dx, dy = gx - q[0, 0], gy - q[0, 1]
        b1 = (dx * v1[1] - v1[0] * dy) / den
        b2 = (v0[0] * dy - dx * v0[1]) / den
        b0 = 1 - b1 - b2
        # Inside, or within about a texel outside its edges.
        el = np.linalg.norm(q - np.roll(q, -1, 0), axis=1)
        h = abs(den) / np.maximum(el, 1e-9)  # heights over each edge
        m = (b0 >= -1.0 / h[1]) & (b1 >= -1.0 / h[2]) & (b2 >= -1.0 / h[0])
        if not m.any():
            continue
        b = np.stack([b0, b1, b2], 1)[m]
        inside = (b >= 0).all(1)
        xs.append(gx[m])
        ys.append(gy[m])
        ts.append(np.full(m.sum(), t))
        bs.append(np.where(inside[:, None], b, np.clip(b, 0, None) / np.clip(b, 0, None).sum(1, keepdims=True)))
        # (texels just outside keep the clamped edge point)
    xs, ys, ts, bs = map(np.concatenate, (xs, ys, ts, bs))
    # Texels claimed by several triangles: the one with the point most inside.
    score = bs.min(1)
    order = np.lexsort((-score, ys * size + xs))
    lin = (ys * size + xs)[order]
    keep = np.ones(len(order), bool)
    keep[1:] = lin[1:] != lin[:-1]
    o = order[keep]
    return xs[o], ys[o], ts[o], bs[o]


def sample(img, uv):
    """Bilinear sample (float, wraps) of an (h, w, c) image at uv (0..1)."""
    h, w = img.shape[:2]
    x = uv[:, 0] * w - 0.5
    y = uv[:, 1] * h - 0.5
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    x0, x1 = x0 % w, (x0 + 1) % w
    y0, y1 = y0 % h, (y0 + 1) % h
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
            + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def bake(hi, lo, size, k=32, chunk=200000):
    """Bake the high-poly's maps into the low-poly's atlas.

    hi: P, N, TAN (xyzw), UV, T (triangles), group (per triangle), maps
        {name: float image}, normal_map name.
    lo: P, N, TAN, UV, T, group (per triangle).
    Returns {name: (size, size, c) float image} (normal map re-encoded)."""
    xs, ys, ts, bs = rasterize(lo["UV"], lo["T"], size)
    LT = lo["T"][ts]

    def lerp(a):
        return (a[LT] * bs[:, :, None]).sum(1)
    p = lerp(lo["P"])
    n_lo = lerp(lo["N"])
    t_lo = lerp(lo["TAN"][:, :3])
    w_lo = np.sign(lo["TAN"][LT[:, 0], 3])
    # High-poly lookup restricted to the same bone group (the robot's parts
    # are nested shells; a point never snaps onto another part).
    HT = hi["T"]
    # Candidates: triangles with a corner, edge midpoint or centre near the
    # point (a centre alone would miss the middle of a long triangle).
    hp = hi["P"][HT]
    probes = np.concatenate([hp, (hp + np.roll(hp, -1, 1)) * 0.5, hp.mean(1, keepdims=True)], 1)  # (t, 7, 3)
    fn_hi, _ = face_normals(hi["P"], HT)
    best_t = np.zeros(len(p), np.int64)
    best_b = np.zeros((len(p), 3))
    lo_group = lo["group"][ts]
    nl = n_lo / np.maximum(np.linalg.norm(n_lo, axis=1, keepdims=True), 1e-12)
    for g in np.unique(lo_group):
        sel_hi = np.nonzero(hi["group"] == g)[0]
        sel = np.nonzero(lo_group == g)[0]
        if len(sel_hi) == 0:
            sel_hi = np.arange(len(HT))
        tree = cKDTree(probes[sel_hi].reshape(-1, 3))
        kk = min(k, len(sel_hi) * 7)
        for s0 in range(0, len(sel), chunk):
            s = sel[s0:s0 + chunk]
            _, cand = tree.query(p[s], kk)
            cand = sel_hi[cand.reshape(len(s), kk) // 7]
            best = np.full(len(s), np.inf)
            for j in range(kk):
                tri = cand[:, j]
                a, b, c = (hi["P"][HT[tri, i]] for i in range(3))
                bb = closest_on_triangles(p[s], a, b, c)
                q = (np.stack([a, b, c], 1) * bb[:, :, None]).sum(1)
                d = np.linalg.norm(q - p[s], axis=1)
                # Facing away from the low-poly surface (the side of a step,
                # the back of a plate): only if nothing facing the same way
                # is about as close.
                d = d + 0.006 * np.clip(1.0 - (fn_hi[tri] * nl[s]).sum(1), 0.0, 2.0)
                better = d < best
                best = np.where(better, d, best)
                best_t[s[better]] = tri[better]
                best_b[s[better]] = bb[better]
    HTb = HT[best_t]

    def hlerp(a):
        return (a[HTb] * best_b[:, :, None]).sum(1)
    uv_hi = hlerp(hi["UV"])
    out = {}
    for name, img in hi["maps"].items():
        v = sample(img, uv_hi)
        if name == hi["normal_map"]:
            # Shading normal of the high-poly at this point...
            nh = hlerp(hi["N"])
            nh /= np.maximum(np.linalg.norm(nh, axis=1, keepdims=True), 1e-12)
            th = hlerp(hi["TAN"][:, :3])
            th /= np.maximum(np.linalg.norm(th, axis=1, keepdims=True), 1e-12)
            bh = np.cross(nh, th) * np.sign(hi["TAN"][HTb[:, 0], 3])[:, None]
            tn = v * 2.0 - 1.0
            world = th * tn[:, :1] + bh * tn[:, 1:2] + nh * tn[:, 2:3]
            world /= np.maximum(np.linalg.norm(world, axis=1, keepdims=True), 1e-12)
            # ...in the low-poly's (interpolated) tangent frame.
            tl = t_lo / np.maximum(np.linalg.norm(t_lo, axis=1, keepdims=True), 1e-12)
            bl = np.cross(nl, tl) * w_lo[:, None]
            M = np.stack([tl, bl, nl], 2)  # columns
            c = np.linalg.solve(M, world[:, :, None])[:, :, 0]
            c[:, 2] = np.maximum(c[:, 2], 0.05)
            c /= np.linalg.norm(c, axis=1, keepdims=True)
            v = c * 0.5 + 0.5
        im = np.zeros((size, size, img.shape[2]))
        im[ys, xs] = v
        out[name] = im
    filled = np.zeros((size, size), bool)
    filled[ys, xs] = True
    # Pad: every empty texel takes its nearest baked texel (no seams at any
    # mip level).
    _, (iy, ix) = distance_transform_edt(~filled, return_indices=True)
    for name in out:
        out[name] = out[name][iy, ix]
    return out, filled
