"""Build the robot's distant-view mesh (robot_enemy_far.glb).

  gltfpack -i robot_enemy.glb -o far.glb -si 0.45 -sa -kn -km -ke -ac -af 0 -noq
  python3 tools/make_robot_far.py far.glb assets/characters/robot/robot_enemy_far.glb

Strips textures and animations (the game reuses the main robot's materials
and skeleton; only the simplified, still-skinned meshes are needed).
"""
import json, struct, sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
jlen = struct.unpack("<I", data[12:16])[0]
js = json.loads(data[20:20 + jlen])
off = 20 + jlen
blen = struct.unpack("<I", data[off:off + 4])[0]
binbuf = data[off + 8:off + 8 + blen]
js.pop("images", None)
js.pop("textures", None)
js.pop("samplers", None)
js.pop("animations", None)
for m in js.get("materials", []):
    pbr = m.get("pbrMetallicRoughness", {})
    pbr.pop("baseColorTexture", None)
    pbr.pop("metallicRoughnessTexture", None)
    for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        m.pop(k, None)
for k in ("extensionsUsed", "extensionsRequired"):
    if k in js:
        js[k] = [e for e in js[k] if e != "EXT_texture_webp"]
        if not js[k]:
            js.pop(k)
# Keep only buffer data still referenced (drop the embedded images).
used = sorted({a["bufferView"] for a in js["accessors"] if "bufferView" in a})
remap, newbin = {}, bytearray()
views = []
for old in used:
    bv = dict(js["bufferViews"][old])
    start = bv.get("byteOffset", 0)
    chunk = binbuf[start:start + bv["byteLength"]]
    while len(newbin) % 4:
        newbin.append(0)
    bv["byteOffset"] = len(newbin)
    newbin += chunk
    remap[old] = len(views)
    views.append(bv)
for a in js["accessors"]:
    if "bufferView" in a:
        a["bufferView"] = remap[a["bufferView"]]
js["bufferViews"] = views
while len(newbin) % 4:
    newbin.append(0)
binbuf = bytes(newbin)
js["buffers"] = [{"byteLength": len(binbuf)}]
j = json.dumps(js, separators=(",", ":")).encode()
j += b" " * ((4 - len(j) % 4) % 4)
total = 12 + 8 + len(j) + 8 + len(binbuf)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, total))
    f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
    f.write(struct.pack("<II", len(binbuf), 0x004E4942) + binbuf)
