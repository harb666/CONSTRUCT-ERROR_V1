#!/usr/bin/env python3
"""Rocket launcher: puts the rocket's nose cone (the separate part sitting in
the bore) into its own mesh node "Warhead"; the rest becomes "Launcher".
Same vertices, UVs and material - only the triangles are split - so the
model looks exactly as before, and the game can hide the loaded rocket when
it fires and show it again when reloaded.

    python3 tools/split_rocket_warhead.py in.glb out.glb
"""
import json, struct, sys
import numpy as np


def main(src, dst):
    b = open(src, 'rb').read()
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    bl = struct.unpack('<I', b[20 + jl:24 + jl])[0]
    binc = bytearray(b[28 + jl:28 + jl + bl])

    def acc(i):
        a = j['accessors'][i]
        bv = j['bufferViews'][a['bufferView']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a['componentType']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        size = np.dtype(dt).itemsize * n
        stride = bv.get('byteStride', size)
        raw = np.frombuffer(bytes(binc), np.uint8, count=stride * (a['count'] - 1) + size, offset=off)
        idx = np.arange(a['count']) * stride
        rows = np.stack([raw[i:i + size] for i in idx]) if stride != size else raw.reshape(a['count'], size)
        return rows.copy().view(dt).reshape(a['count'], n)

    assert len(j['meshes']) == 1 and len(j['meshes'][0]['primitives']) == 1
    prim = j['meshes'][0]['primitives'][0]
    P = acc(prim['attributes']['POSITION'])
    I = acc(prim['indices']).reshape(-1, 3).astype(np.int64)
    # Parts = triangles connected through shared (welded) positions.
    key = np.round(P * 1e4).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    T = weld[I]
    parent = np.arange(weld.max() + 1)

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, c, d in T:
        ra = find(a)
        parent[find(c)] = ra
        parent[find(d)] = ra
    comp = np.array([find(t[0]) for t in T])
    # The warhead: the small part on the bore's axis at the muzzle end (-X).
    best = None
    for cid in np.unique(comp):
        v = P[np.unique(I[comp == cid])]
        r = np.sqrt((v[:, 1] + 0.04) ** 2 + v[:, 2] ** 2).max()
        if r < 0.08 and v[:, 0].min() < -0.9:
            best = cid
    assert best is not None, 'warhead part not found'
    war = I[comp == best].ravel().astype(np.uint32)
    body = I[comp != best].ravel().astype(np.uint32)

    def add_indices(arr):
        while len(binc) % 4:
            binc.append(0)
        off = len(binc)
        binc.extend(arr.tobytes())
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes, 'target': 34963})
        j['accessors'].append({'bufferView': len(j['bufferViews']) - 1, 'componentType': 5125, 'count': int(arr.size), 'type': 'SCALAR'})
        return len(j['accessors']) - 1

    def add_attr(arr, kind):
        while len(binc) % 4:
            binc.append(0)
        off = len(binc)
        arr = np.ascontiguousarray(arr, np.float32)
        binc.extend(arr.tobytes())
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes, 'target': 34962})
        a = {'bufferView': len(j['bufferViews']) - 1, 'componentType': 5126, 'count': int(arr.shape[0]), 'type': kind}
        if kind == 'VEC3':
            a['min'] = arr.min(0).tolist()
            a['max'] = arr.max(0).tolist()
        j['accessors'].append(a)
        return len(j['accessors']) - 1

    prim['indices'] = add_indices(body)
    # The warhead gets its own compact copy of just the vertices it uses.
    used, local = np.unique(war, return_inverse=True)
    wprim = dict(prim)
    wprim['attributes'] = {}
    for name, ai in prim['attributes'].items():
        kind = j['accessors'][ai]['type']
        wprim['attributes'][name] = add_attr(acc(ai)[used], kind)
    wprim['indices'] = add_indices(local.astype(np.uint32))
    j['meshes'][0]['name'] = 'Launcher'
    j['meshes'].append({'name': 'Warhead', 'primitives': [wprim]})
    root = j['scenes'][j.get('scene', 0)]['nodes']
    assert len(root) == 1
    j['nodes'][root[0]]['name'] = 'Launcher'
    j['nodes'].append({'name': 'Warhead', 'mesh': len(j['meshes']) - 1})
    root.append(len(j['nodes']) - 1)
    while len(binc) % 4:
        binc.append(0)
    j['buffers'][0]['byteLength'] = len(binc)
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binc))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js
    out += struct.pack('<II', len(binc), 0x004E4942) + bytes(binc)
    open(dst, 'wb').write(out)
    print('warhead %d triangles (%d vertices), launcher %d' % (war.size // 3, used.size, body.size // 3))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
