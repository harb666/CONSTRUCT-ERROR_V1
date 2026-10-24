"""Bitcoin token face (RecoveryDrops tokens): a gold coin face, a raised
rim and a bold embossed bitcoin B (a B with two bars through the top and
bottom). Writes assets/ui/pickups/bitcoin_face.png (128 px, RGBA).

    python3 tools/make_bitcoin_face.py
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math

N = 128
S = 4  # supersampled
W = N * S
img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
c = W / 2
# Coin body: radial gold.
for i in range(200, 0, -1):
    r = c * i / 200
    k = i / 200
    col = (int(255 - 40 * k), int(214 - 70 * k), int(80 - 60 * k), 255)
    d.ellipse([c - r, c - r, c + r, c + r], fill=col)
# Rim: a darker ring then a bright inner edge.
d.ellipse([0, 0, W - 1, W - 1], outline=(150, 95, 10, 255), width=7 * S)
d.ellipse([9 * S, 9 * S, W - 9 * S, W - 9 * S], outline=(255, 236, 150, 255), width=2 * S)
# The B: a dark shadow, then the lighter face (embossed).
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 78 * S)


def glyph(dx: float, dy: float, col) -> None:
    box = d.textbbox((0, 0), "B", font=font)
    w = box[2] - box[0]
    h = box[3] - box[1]
    x = c - w / 2 - box[0] + dx
    y = c - h / 2 - box[1] + dy
    d.text((x, y), "B", font=font, fill=col)
    # The two bars through the top and bottom.
    for bx in (x + box[0] + w * 0.30, x + box[0] + w * 0.56):
        d.rectangle([bx, y + box[1] - 9 * S, bx + 7 * S, y + box[1] + 4 * S], fill=col)
        d.rectangle([bx, y + box[3] - 4 * S, bx + 7 * S, y + box[3] + 9 * S], fill=col)


glyph(3 * S, 3 * S, (120, 70, 0, 255))
glyph(0, 0, (255, 246, 196, 255))
img = img.resize((N, N), Image.LANCZOS)
img.save("assets/ui/pickups/bitcoin_face.png")
print("assets/ui/pickups/bitcoin_face.png")
