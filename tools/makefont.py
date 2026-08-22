#!/usr/bin/env python3
"""Render a high-resolution font atlas for the game to draw text with.

The original font lives in ANIM.SKI as 59 glyphs six pixels tall, which is too
little detail to upscale usefully - see MODERNIZATION.md section 12. This bakes
a real typeface into FONTHI.DAT at pixelScale resolution instead.

Advance widths are taken from the original glyphs and left alone, so every
existing screen layout still lines up; only the shapes drawn inside those
advances change. Run it after changing SCALE or the typeface:

    python3 tools/makefont.py
"""
import struct, sys
from PIL import Image, ImageDraw, ImageFont

SCALE   = 4
TTF     = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
OUT     = "FONTHI.DAT"
ANIM    = "ANIM.SKI"

# Glyph index -> character, mirroring the case statement in SJ3Graph.DoFont
# (that code computes t, and the glyph drawn is t+1).
CHARS = {}
for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"): CHARS[i + 1] = c
CHARS[27] = "Ä"; CHARS[28] = "Ö"; CHARS[29] = "Å"
CHARS[30] = "0"
for i, c in enumerate("123456789"): CHARS[31 + i] = c
for i, c in enumerate([":", ".", "?", "!", "*", "-", "+", ",", "(", ")"]):
    CHARS[40 + i] = c
CHARS[50] = "m"; CHARS[51] = '"'; CHARS[52] = "'"; CHARS[53] = "#"
CHARS[54] = "Ø"; CHARS[55] = "Ü"; CHARS[56] = "ß"
CHARS[57] = "/"; CHARS[58] = "Æ"; CHARS[59] = "%"


def read_metrics(path):
    """Recover each glyph's box from ANIM.SKI the way LoadAnim reads it."""
    data = open(path, "rb").read()
    pos, n, out = 0, 0, {}
    def rb():
        nonlocal pos
        v = data[pos]; pos += 1; return v
    x, y = rb(), rb()
    while True:
        n += 1
        pos += x * y
        rb(); rb()                       # hotspot, unused by the font
        if n in CHARS:
            out[n] = (x, y)
        x, y = rb(), rb()
        if (x, y) == (255, 255) or n > 250:
            break
    return out


def fit_size(font_path, target_cap):
    """Largest size whose capital height still fits the original box."""
    best = 8
    for size in range(8, 80):
        f = ImageFont.truetype(font_path, size)
        box = f.getbbox("H")
        if (box[3] - box[1]) <= target_cap:
            best = size
        else:
            break
    return best


def main():
    metrics = read_metrics(ANIM)
    if len(metrics) != len(CHARS):
        sys.exit(f"expected {len(CHARS)} glyphs, recovered {len(metrics)}")

    cell_h = max(h for _, h in metrics.values()) * SCALE
    size = fit_size(TTF, cell_h - SCALE)      # leave a little room under caps
    font = ImageFont.truetype(TTF, size)
    ascent, _ = font.getmetrics()

    glyphs = {}
    for idx, ch in CHARS.items():
        adv = metrics[idx][0] * SCALE
        box = font.getbbox(ch)
        gw, gh = box[2] - box[0], box[3] - box[1]
        img = Image.new("L", (max(gw, 1) + 2, max(gh, 1) + 2), 0)
        ImageDraw.Draw(img).text((1 - box[0], 1 - box[1]), ch, fill=255, font=font)
        # centre horizontally in the advance the original glyph occupied, and
        # sit on a baseline shared by every glyph
        ox = (adv - img.width) // 2
        oy = (box[1] - ascent) + cell_h
        glyphs[idx] = (img, ox, oy)

    with open(OUT, "wb") as f:
        f.write(b"SJHF")
        f.write(struct.pack("<BBB", 1, SCALE, max(CHARS)))
        for idx in range(1, max(CHARS) + 1):
            if idx not in glyphs:
                f.write(struct.pack("<BBbb", 0, 0, 0, 0)); continue
            img, ox, oy = glyphs[idx]
            f.write(struct.pack("<BBbb", img.width, img.height,
                                max(-128, min(127, ox)), max(-128, min(127, oy))))
            f.write(img.tobytes())

    print(f"{OUT}: {len(glyphs)} glyphs, {size}px {TTF.split('/')[-1]}, "
          f"cell height {cell_h}, {open(OUT,'rb').seek(0,2) or 0}")
    import os; print(f"  {os.path.getsize(OUT)} bytes")


if __name__ == "__main__":
    main()
