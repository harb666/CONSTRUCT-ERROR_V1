"""Builds the Frost Byte weapon asset from the owner's Frost_byte_v1.glb.

  npx gltfpack -i Frost_byte_v1.glb -o simplified.glb -si 0.5 -slb -kn -km -noq
  python3 tools/build_frost_byte.py simplified.glb assets/weapons/frost_byte/frost_byte.glb

gltfpack: 99k -> 49k triangles (same look, like the rocket launcher). This
script re-packs its three textures (PNG, base colour / normal 2048, metal-
roughness 4096) as JPEG at most 2048 px, like the other weapons, so the
file and the phone's memory stay small. Geometry and UVs untouched.
"""
import io, json, struct, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
b = open(src, 'rb').read()
L = struct.unpack('<I', b[12:16])[0]
j = json.loads(b[20:20 + L])
off = 20 + L + 8
blob = b[off:off + struct.unpack('<I', b[20 + L:24 + L])[0]]
views = j['bufferViews']
img_views = {im['bufferView'] for im in j.get('images', [])}
new_blob = bytearray()
for i, v in enumerate(views):
    data = blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
    if i in img_views:
        im = Image.open(io.BytesIO(data)).convert('RGB')
        if max(im.size) > 2048:
            im = im.resize((2048, 2048), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, 'JPEG', quality=92)
        data = out.getvalue()
    while len(new_blob) % 4:
        new_blob += b'\0'
    v['byteOffset'] = len(new_blob)
    v['byteLength'] = len(data)
    new_blob += data
for im in j.get('images', []):
    im['mimeType'] = 'image/jpeg'
while len(new_blob) % 4:
    new_blob += b'\0'
j['buffers'] = [{'byteLength': len(new_blob)}]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4:
    js += b' '
total = 12 + 8 + len(js) + 8 + len(new_blob)
with open(dst, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
    f.write(struct.pack('<II', len(new_blob), 0x004E4942) + bytes(new_blob))
print('wrote', dst, total // 1024, 'KB')
