"""Lager's waffle look (owner asked: she's based on waffles - "make the
ornament on her hair look more like waffles instead of sweetcorn" and "make
her suit reflect waffles too"; option A of the mockup, with "the butter like
icecream melting like what's on the rest of her armour").

Used by tools/build_lager.py:
- `recolour(...)`: her shiny gold armour becomes toasted waffle - matte,
  golden-brown, from the gold's own light / dark (every modelled panel, edge
  and recess kept; the square panels read as waffle pockets). Only the gold
  below the head; the white cream swirls, black joints, glowing lights, face
  and hair keep their look.
- `bun_triangles(...)`: the corn-cob bun on her head (all above BUN_CUT, and
  the gold kernels down to BUN_LOW), removed; `seal(...)` closes the opening
  it leaves in the hair top.
- `ornament()`: two stacked square waffles (deep pockets both faces,
  toasted crust with the iron's seam) and a swirl of melting ice cream on
  top - the cream of her armour's swirls - running into a puddle and down
  over the edges. Bind-pose metres, closed shapes (so the cap tool,
  tools/build_mesh_caps.gd, finds no holes in them); skinned to the head.
"""
import numpy as np

BUN_CUT, BUN_LOW = 1.56, 1.50
# Ornament placement: centre of the bun's base (bind pose), lean back.
BASE = np.array([-0.004, 1.545, -0.077])
TILT = np.radians(-12.0)
# Toasted waffle colours, dark (pocket) -> light (crust top).
RAMP = np.array([[0.30, 0.15, 0.05], [0.56, 0.30, 0.10], [0.80, 0.52, 0.22], [0.96, 0.76, 0.42]])
# The cream of her armour's swirls.
CREAM = np.array([1.0, 0.97, 0.90])
CREAM_SHADE = np.array([0.88, 0.80, 0.68])


def ramp_image(n=64):
    """The ornament's colours: a small texture, top half the waffle ramp
    (u = dark pocket -> light crust), bottom half the cream (u = light ->
    shaded). (Godot's import doesn't reliably turn vertex colours on.)"""
    u = np.linspace(0, 1, n)
    img = np.zeros((n, n, 3))
    img[: n // 2] = ramp(u)[None]
    img[n // 2:] = (CREAM[None] * (1 - u[:, None]) + CREAM_SHADE[None] * u[:, None])[None]
    return img


def ramp(t):
    xs = np.linspace(0, 1, len(RAMP))
    t = np.clip(t, 0, 1)
    return np.stack([np.interp(t, xs, RAMP[:, i]) for i in range(3)], -1)


def gold(C):
    """Gold-coloured (armour gold, the bun's kernels): not white, not the glow."""
    R, G, B = C[..., 0], C[..., 1], C[..., 2]
    gr = G / np.maximum(R, 1e-3)
    return (R > 0.42) & (R - B > 0.22) & (gr > 0.42) & (gr < 0.86)


# --- Textures -------------------------------------------------------------

def texel_heights(P, UV, I, size):
    """Bind-pose height (y) of each texel of the atlas (NaN where unused)."""
    R = size
    hy = np.full((R, R), np.nan, np.float32)
    uv = UV[I] * R - 0.5
    for t in range(len(I)):
        a, b, c = uv[t]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))), R - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))), R - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        l2 = 1 - l0 - l1
        e = -0.6 / max(abs(den), 1) ** 0.5
        inside = (l0 >= e) & (l1 >= e) & (l2 >= e)
        if inside.any():
            L = np.stack([l0[inside], l1[inside], l2[inside]], 1)
            hy[ys[inside], xs[inside]] = L @ P[I[t], 1]
    return hy


def recolour(col, mr, P, UV, I):
    """col: RGB 0-1 base colour; mr: RGB 0-1 metallic-roughness (G rough, B
    metal). Returns both with the armour's gold toasted."""
    from scipy import ndimage
    hy = texel_heights(P, UV, I, col.shape[0])
    used = ~np.isnan(hy)
    # Unused texels (the gaps between the atlas's many small islands) count
    # in, so the clean-up below doesn't eat the small islands away.
    m = gold(col) & ((hy < 1.30) | ~used)
    m = ndimage.binary_opening(m, iterations=2)   # not the hair's thin gold streaks
    m = ndimage.binary_closing(m, iterations=2) & used
    R, G, B = col[..., 0], col[..., 1], col[..., 2]
    lum = 0.3 * R + 0.59 * G + 0.11 * B
    lo, hi = np.percentile(lum[m], 3), np.percentile(lum[m], 97)
    t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1) ** 1.25
    w = ndimage.gaussian_filter(m.astype(np.float32), 1.0)[..., None]
    col2 = col * (1 - w) + ramp(t) * w
    mr2 = mr.copy()
    mr2[..., 2] = mr[..., 2] * (1 - w[..., 0])
    mr2[..., 1] = mr[..., 1] * (1 - w[..., 0]) + 0.62 * w[..., 0]
    return col2, mr2, float(m.mean())


# --- The bun --------------------------------------------------------------

def bun_triangles(P, I, C):
    """Triangles of the corn-cob bun on her head."""
    y = P[I][:, :, 1]
    g = gold(C)[I].all(1)
    c = P[I].mean(1)
    near = (np.abs(c[:, 0]) < 0.2) & (c[:, 2] > -0.3)
    return (y.min(1) > BUN_CUT) | ((y.min(1) > BUN_LOW) & g & near)


def seal(P, I, removed):
    """Fan caps for the openings `removed` triangles leave (loops of edges
    now used once). Returns [(rim vertex ids in order, centre point)]."""
    key = np.round(P / 1e-5).astype(np.int64)
    _, wid = np.unique(key, axis=0, return_inverse=True)
    wid = wid.ravel()
    rep = {}
    for v in range(len(P)):
        rep.setdefault(wid[v], v)

    def edge_count(tris):
        T = wid[tris]
        e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), 1)
        u, n = np.unique(e, axis=0, return_counts=True)
        return {tuple(k): c for k, c in zip(u, n)}
    before = edge_count(I)
    kept = I[~removed]
    after = edge_count(kept)
    # Directed boundary edges of the kept triangles (new ones only), walked
    # the other way round so the caps face out; a rim that pinches (two
    # loops through one point) is split into its loops.
    T = wid[kept]
    nxt = {}
    total = 0
    for a, b in np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]):
        k = (min(a, b), max(a, b))
        if after.get(k, 0) == 1 and before.get(k, 0) >= 2:
            nxt.setdefault(b, []).append(a)
            total += 1
    loops = []
    while nxt:
        s0 = next(iter(nxt))
        path = [s0]
        seen = {s0: 0}
        cur = s0
        while cur in nxt:
            n = nxt[cur].pop()
            if not nxt[cur]:
                del nxt[cur]
            if n in seen:   # closed a loop: take it off the path
                i = seen[n]
                lp = path[i:]
                if len(lp) >= 3:
                    loops.append([rep[w] for w in lp])
                for w in lp[1:]:
                    del seen[w]
                path = path[:i + 1]
                cur = n
                if cur not in nxt:
                    break
                continue
            seen[n] = len(path)
            path.append(n)
            cur = n
    used = sum(len(lp) for lp in loops)
    if used != total:
        print("hair ornament: %d of %d rim edges not in a closed loop" % (total - used, total))
    return [(lp, P[lp].mean(0)) for lp in loops]


# --- Ornament -------------------------------------------------------------

def _orient(t, want):
    """Turn triangles (n,3,3) to face along `want` (n,3)."""
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    flip = (n * want).sum(1) < 0
    t = t.copy()
    t[flip] = t[flip][:, [0, 2, 1]]
    return t, flip


def _grid_coords(half, per, w, bev):
    xs = {-half, half}
    k = 0
    while True:
        L = -half + k * per
        if L > half + 1e-9:
            break
        for d in (-w - bev, -w, w, w + bev):
            if -half < L + d < half:
                xs.add(round(L + d, 7))
        k += 1
    return np.array(sorted(xs))


def waffle(size, thick, cells=4, depth=0.016, w=0.0085, bev=0.006):
    """Closed square waffle centred on the origin: pocketed top and bottom
    (exact grid, not a dense height map), puffed crust sides with the
    iron's dark seam. Returns triangles (n,3,3) and their corners' place on
    the waffle colour ramp (n,3)."""
    half, per = size / 2, size / cells
    g = _grid_coords(half, per, w, bev)

    def ridge(a):
        f = (a + half) / per
        d = np.abs(f - np.round(f)) * per
        return 1 - np.clip((d - w) / bev, 0, 1)
    X, Z = np.meshgrid(g, g, indexing="ij")
    r = np.maximum(ridge(X), ridge(Z))
    edge = np.minimum(half - np.abs(X), half - np.abs(Z))
    col = 0.25 + 0.62 * r - 0.25 * (edge < 0.012)
    tris, cols, want = [], [], []
    n = len(g)
    for s in (1, -1):
        Y = s * (thick / 2 - depth + depth * r)
        V = np.stack([X, Y, Z], -1)
        for i in range(n - 1):
            for j in range(n - 1):
                q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                    tris.append([V[a] for a in tri])
                    cols.append([col[a] for a in tri])
                    want.append([0, s, 0])
    # Sides: the face's border points, top rim to bottom rim (closed).
    ring = [(x, -half) for x in g[:-1]] + [(half, z) for z in g[:-1]] + \
           [(x, half) for x in g[::-1][:-1]] + [(-half, z) for z in g[::-1][:-1]]
    ring.append(ring[0])
    ys = np.linspace(thick / 2, -thick / 2, 13)
    for q in range(len(ring) - 1):
        (x0, z0), (x1, z1) = ring[q], ring[q + 1]
        out = np.array([x0 + x1, 0, z0 + z1])
        out /= max(np.linalg.norm(out), 1e-9)
        for k in range(len(ys) - 1):
            pts = []
            for (x, z) in ((x0, z0), (x1, z1)):
                for y in (ys[k], ys[k + 1]):
                    nrm = np.array([x, 0, z]) / max(np.hypot(x, z), 1e-9)
                    bulge = 0.0055 * max(np.cos(y / (thick / 2) * np.pi / 2), 0) ** 0.6
                    pts.append(np.array([x, y, z]) + nrm * bulge)
            seam = np.exp(-(((ys[k] + ys[k + 1]) / 2) / 0.0035) ** 2)
            c = 0.55 - 0.32 * seam
            for tri in ((0, 1, 3), (0, 3, 2)):
                tris.append([pts[a] for a in tri])
                cols.append([c] * 3)
                want.append(out)
    t, flip = _orient(np.array(tris), np.array(want, float))
    c = np.array(cols)
    c[flip] = c[flip][:, [0, 2, 1]]
    return t, c


def _surface(F, nu, nv, wrap_u=True):
    """Triangles of a grid surface F (nu x nv x 3) (u wraps round)."""
    tris = []
    for i in range(nu if wrap_u else nu - 1):
        i2 = (i + 1) % nu
        for j in range(nv - 1):
            a, b, c, d = F[i, j], F[i2, j], F[i2, j + 1], F[i, j + 1]
            tris += [[a, b, c], [a, c, d]]
    return tris


def ice_cream(top, half):
    """Melting soft-serve swirl on a waffle's top (waffle-local, top face at
    y = `top`, square half-size `half`), the cream of her armour's swirls:
    a swirl with deep spiral ridges and a curled tip, slumping into a pool
    that spreads over the pockets and runs over the edges in drips ending in
    drops. Returns triangles (n,3,3) and each corner's shade (0 cream ..
    1 shaded: grooves, undersides)."""
    pieces = []   # (triangles with a 4th shade component, outward fn)
    drips = [(np.radians(a), L) for a, L in ((-25, 0.040), (50, 0.024), (130, 0.046), (205, 0.030), (290, 0.020))]

    def edge_dist(th):
        return half / max(abs(np.cos(th)), abs(np.sin(th)))

    def rim(th):
        r = 0.068 * (1 + 0.14 * np.sin(5 * th + 0.7) + 0.07 * np.sin(9 * th + 2.0))
        for a, _ in drips:
            d = np.angle(np.exp(1j * (th - a)))
            r = r + (edge_dist(a) + 0.002 - r) * np.exp(-(d / 0.20) ** 2)
        return r

    def V(x, y, z, sh=0.0):
        return np.array([x, y, z, sh], float)
    # Pool: closed (rounded top, flat underside on the waffle's ridges).
    nu, nv = 120, 8
    th = np.linspace(0, 2 * np.pi, nu, endpoint=False)
    R = np.array([rim(a) for a in th])
    F = np.zeros((nu, nv, 4))
    for j, sv in enumerate(np.linspace(1, 0, nv)):   # rim -> centre
        hgt = 0.0075 * np.sqrt(max(1 - sv ** 2, 0)) + 0.0006
        F[:, j, 0], F[:, j, 1], F[:, j, 2] = R * sv * np.cos(th), top + hgt, R * sv * np.sin(th)
        F[:, j, 3] = 0.25 * sv ** 4
    tri = _surface(F, nu, nv)
    G = np.zeros((nu, 2, 4))
    G[:, 0] = F[:, 0]
    G[:, 1, 0], G[:, 1, 1], G[:, 1, 2], G[:, 1, 3] = R * np.cos(th), top - 0.0008, R * np.sin(th), 0.6
    tri += _surface(G, nu, 2)
    tri += [[V(0, top - 0.0008, 0, 0.6), G[(i + 1) % nu, 1], G[i, 1]] for i in range(nu)]
    pieces.append((tri, lambda c: np.where(c[:, 1:2] > top + 0.0002,
                                           np.array([[0, 1.0, 0]]) + 0 * c[:, :3],
                                           np.c_[c[:, 0], np.full(len(c), -0.02), c[:, 2]])))
    # Swirl: deep spiral ridges (sharp-ish crests, shaded grooves), slumped base.
    H = 0.062
    nu2, nv2 = 96, 48
    th2 = np.linspace(0, 2 * np.pi, nu2, endpoint=False)
    S = np.zeros((nu2, nv2, 4))
    for j, sv in enumerate(np.linspace(0, 1, nv2)):
        rad = 0.054 * (1 - sv ** 2.4) ** 0.45 * (1 + 0.20 * np.exp(-(sv / 0.10) ** 2))
        wave = np.sin(3 * th2 - 11.0 * sv)
        crest = np.sign(wave) * np.abs(wave) ** 0.55
        lobes = 1 + 0.17 * crest * (1 - 0.55 * sv)
        tip = np.array([0.012 * sv ** 4, -0.006 * sv ** 4])
        y = top + 0.006 + H * sv - 0.004 * (1 - sv) ** 8
        S[:, j, 0] = rad * lobes * np.cos(th2) + tip[0]
        S[:, j, 1] = y
        S[:, j, 2] = rad * lobes * np.sin(th2) + tip[1]
        S[:, j, 3] = np.clip(0.55 * (0.4 - crest) / 1.4, 0, 0.55)
    tri = _surface(S, nu2, nv2)
    c0 = S[:, 0].mean(0)
    tri += [[c0, S[(i + 1) % nu2, 0], S[i, 0]] for i in range(nu2)]
    pieces.append((tri, lambda c: np.c_[c[:, 0], np.where(c[:, 1] < top + 0.007, -1.0, c[:, 1] - top - 0.02), c[:, 2]]))
    # Drips over the edges: fat flattened tubes ending in round drops.
    for a, L in drips:
        d = np.array([np.cos(a), 0, np.sin(a)])
        e = edge_dist(a)
        path = [d * (e - 0.012) + [0, top + 0.004, 0], d * (e - 0.003) + [0, top + 0.003, 0],
                d * (e + 0.004) + [0, top - 0.003, 0], d * (e + 0.0065) + [0, top - 0.009, 0]]
        for k in range(1, 6):
            path.append(d * (e + 0.0068) + [0, top - 0.009 - L * k / 5, 0])
        path = np.array(path)
        side = np.cross(d, [0, 1, 0])
        ring_n = 14
        rings = []
        for k, p in enumerate(path):
            fwd = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
            fwd /= np.linalg.norm(fwd)
            up = np.cross(side, fwd)
            rad = 0.0095 * (1 - 0.30 * k / len(path))
            if k == len(path) - 1:
                rad = 0.012   # the drop at the end
            rings.append([np.r_[p + rad * (np.cos(q) * side + 0.6 * np.sin(q) * up), 0.1 + 0.15 * k / len(path)]
                          for q in np.linspace(0, 2 * np.pi, ring_n, endpoint=False)])
        # Round ends: rings closing in like a half ball.
        for end, sgn in ((0, -1), (len(path) - 1, 1)):
            fwd = path[end] - path[end - sgn]
            fwd /= np.linalg.norm(fwd)
            base = np.array(rings[end])
            ctr = path[end]
            extra = []
            for phi in np.radians([30, 55, 75]):
                extra.append([np.r_[ctr + (q[:3] - ctr) * np.cos(phi) + fwd * np.linalg.norm(q[:3] - ctr) * np.sin(phi), q[3]]
                              for q in base])
            cap = np.r_[ctr + fwd * np.linalg.norm(base[:, :3] - ctr, axis=1).mean(), base[0][3]]
            extra.append([cap] * ring_n)
            if sgn > 0:
                rings = rings + extra
                path = np.concatenate([path, [e[0][:3] * 0 + ctr for e in extra]])
            else:
                rings = extra[::-1] + rings
                path = np.concatenate([[ctr for _ in extra], path])
        rings = np.array(rings)
        tri = _surface(np.transpose(rings, (1, 0, 2)), ring_n, len(rings))
        line = path.copy()

        def out_fn(c, line=line):
            dd = np.linalg.norm(c[:, None, :3] - line[None], axis=2)
            return c[:, :3] - line[dd.argmin(1)]
        pieces.append((tri, out_fn))
    ts, shades = [], []
    for tri, out_fn in pieces:
        t4 = np.array(tri, float)
        t = t4[..., :3]
        n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        flip = (n * out_fn(t4.mean(1))).sum(1) < 0
        t4[flip] = t4[flip][:, [0, 2, 1]]
        ts.append(t4[..., :3])
        shades.append(t4[..., 3])
    return np.concatenate(ts), np.concatenate(shades)


def _place(t, rot_y, off):
    cy, sy, cx, sx = np.cos(rot_y), np.sin(rot_y), np.cos(TILT), np.sin(TILT)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    return t @ (Rx @ Ry).T + off


def smooth_normals(t, crease=0.64):
    """Per-corner normals, smoothed over faces whose normals are within
    the crease angle (cos) of each other."""
    fn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    P = t.reshape(-1, 3)
    _, gid = np.unique(np.round(P / 1e-5).astype(np.int64), axis=0, return_inverse=True)
    gid = gid.ravel()
    cf = np.repeat(fn, 3, 0)
    out = cf.copy()
    order = np.argsort(gid, kind="stable")
    for grp in np.split(order, np.flatnonzero(np.diff(gid[order])) + 1):
        if len(grp) > 1:
            g = cf[grp]
            acc = ((g @ g.T) > crease).astype(float) @ g
            out[grp] = acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
    return out


def ornament():
    """{name: (positions (n,3), normals (n,3), uv on ramp_image() (n,2),
    roughness)} - unindexed triangles, bind pose."""
    w1, c1 = waffle(0.25, 0.05)
    w1 = _place(w1, np.radians(8), BASE + [0, 0.026, 0])
    w2, c2 = waffle(0.21, 0.045)
    ic, ci = ice_cream(0.045 / 2, 0.105)
    off2 = BASE + [0.003, 0.072, -0.01]
    w2 = _place(w2, np.radians(40), off2)
    ic = _place(ic, np.radians(40), off2)
    wt = np.concatenate([w1, w2])
    wc = np.concatenate([c1, c2])

    def solid(t, c):   # without the zero-area triangles at the poles
        a = np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1)
        return t[a > 1e-11], c[a > 1e-11]
    wt, wc = solid(wt, wc)
    ic, ci = solid(ic, ci)
    # Texture coordinates on ramp_image(): waffle top half, cream bottom.
    wuv = np.stack([np.clip(wc.ravel(), 0.01, 0.99), np.full(wc.size, 0.25)], -1)
    iuv = np.stack([np.clip(ci.ravel(), 0.01, 0.99), np.full(ci.size, 0.75)], -1)
    return {
        "Waffle": (wt.reshape(-1, 3), smooth_normals(wt), wuv, 0.7),
        "IceCream": (ic.reshape(-1, 3), smooth_normals(ic, 0.3), iuv, 0.25),
    }
