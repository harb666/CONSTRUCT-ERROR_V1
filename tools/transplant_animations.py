"""Copy the animations of one GLB into another, byte for byte.

Used after simplifying a character's meshes (gltfpack also thins animation
keyframes, slightly changing motion): the reduced GLB keeps its lighter
meshes but gets the original, untouched animation data back.
Channels are re-targeted to nodes by name.

usage: python3 tools/transplant_animations.py original.glb reduced.glb out.glb
"""
import json, struct, sys


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", data[off:off + 4])[0]
    return js, bytearray(data[off + 8:off + 8 + blen])


def write_glb(path, js, binbuf):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((4 - len(j) % 4) % 4)
    while len(binbuf) % 4:
        binbuf.append(0)
    total = 12 + 8 + len(j) + 8 + len(binbuf)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(binbuf), 0x004E4942) + bytes(binbuf))


def accessor_bytes(js, binbuf, ai):
    a = js["accessors"][ai]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: 4, 5123: 2, 5121: 1, 5125: 4, 5122: 2, 5120: 1}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    elem = comp * n
    stride = bv.get("byteStride", elem)
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = bytearray()
    for i in range(a["count"]):
        out += binbuf[start + i * stride:start + i * stride + elem]
    return out


def main(orig_path, red_path, out_path):
    oj, ob = read_glb(orig_path)
    rj, rb = read_glb(red_path)
    name_to_red = {}
    for i, n in enumerate(rj["nodes"]):
        if "name" in n:
            if n["name"] in name_to_red:
                sys.exit("duplicate node name in reduced file: " + n["name"])
            name_to_red[n["name"]] = i
    rj["animations"] = []
    cache = {}

    def copy_accessor(ai):
        if ai in cache:
            return cache[ai]
        raw = accessor_bytes(oj, ob, ai)
        while len(rb) % 4:
            rb.append(0)
        bv = {"buffer": 0, "byteOffset": len(rb), "byteLength": len(raw)}
        rb.extend(raw)
        rj["bufferViews"].append(bv)
        a = dict(oj["accessors"][ai])
        a["bufferView"] = len(rj["bufferViews"]) - 1
        a.pop("byteOffset", None)
        a.pop("sparse", None)
        rj["accessors"].append(a)
        cache[ai] = len(rj["accessors"]) - 1
        return cache[ai]

    for anim in oj.get("animations", []):
        samplers = [{"input": copy_accessor(s["input"]), "output": copy_accessor(s["output"]),
                     "interpolation": s.get("interpolation", "LINEAR")} for s in anim["samplers"]]
        channels = []
        for c in anim["channels"]:
            node_name = oj["nodes"][c["target"]["node"]].get("name")
            if node_name not in name_to_red:
                sys.exit("animated node missing in reduced file: %s" % node_name)
            channels.append({"sampler": c["sampler"], "target": {"node": name_to_red[node_name], "path": c["target"]["path"]}})
        new = {"name": anim.get("name", ""), "samplers": samplers, "channels": channels}
        rj["animations"].append(new)
    rj["buffers"][0]["byteLength"] = len(rb)
    write_glb(out_path, rj, rb)


if __name__ == "__main__":
    main(*sys.argv[1:4])
