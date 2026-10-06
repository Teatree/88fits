"""The musical notes atlas for Fx.note (pass 46, the Guitarra's cone of melody): game/art/fx/notes.png.

Four glyphs side by side in 128 px cells (a quarter note, an eighth note with its flag, two beamed eighths, two beamed
sixteenths), drawn as shapes (no font: a phone has none of these glyphs to lean on), white with a dark ink outline, so
the note shader's tint colours the white and leaves the outline dark. Drawn at four times the size and scaled down for
smooth edges.

    python tools/gen_notes.py            (then the Godot --import, so the game reads the PNG)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "art", "fx", "notes.png")
CELL = 128
CELLS = 4
SS = 4                   # supersampling
OUTLINE = 5.0            # px of ink round each glyph, at the final size
INK = (38, 26, 18)
FILL = (255, 255, 255)


def _p(x, y, cx):
    """A point in a cell's 128-unit space, at the supersampled scale, in cell `cx`."""
    return ((cx * CELL + x) * SS, y * SS)


def _head(d, cx, x, y, rx=19.0, ry=13.5, tilt=-22.0):
    """A note head: an ellipse tipped up to the right, as engraved."""
    t = math.radians(tilt)
    pts = []
    for k in range(48):
        a = math.tau * k / 48
        ex, ey = math.cos(a) * rx, math.sin(a) * ry
        pts.append(_p(x + ex * math.cos(t) - ey * math.sin(t), y + ex * math.sin(t) + ey * math.cos(t), cx))
    d.polygon(pts, fill=255)


def _stem(d, cx, x, y0, y1, w=6.5):
    d.polygon([_p(x - w / 2, y0, cx), _p(x + w / 2, y0, cx), _p(x + w / 2, y1, cx), _p(x - w / 2, y1, cx)], fill=255)


def _beam(d, cx, x0, y0, x1, y1, h=11.0):
    d.polygon([_p(x0, y0, cx), _p(x1, y1, cx), _p(x1, y1 + h, cx), _p(x0, y0 + h, cx)], fill=255)


def _flag(d, cx, x, y):
    """The eighth note's flag: from the top of the stem it swells out to the right and curls down to a point."""
    outer = [(x, y), (x + 4, y + 2), (x + 14, y + 12), (x + 25, y + 24), (x + 29, y + 38), (x + 25, y + 52), (x + 19, y + 60)]
    inner = [(x + 17, y + 47), (x + 18, y + 37), (x + 13, y + 28), (x + 5, y + 22), (x, y + 21)]
    d.polygon([_p(px, py, cx) for px, py in outer + inner], fill=255)


def draw_mask():
    m = Image.new("L", (CELL * CELLS * SS, CELL * SS), 0)
    d = ImageDraw.Draw(m)
    # 0: a quarter note
    _head(d, 0, 50, 94)
    _stem(d, 0, 66.5, 20, 92)
    # 1: an eighth note with its flag
    _head(d, 1, 44, 96)
    _stem(d, 1, 60.5, 16, 94)
    _flag(d, 1, 57.5, 16)
    # 2: two eighths on one beam
    _head(d, 2, 30, 98, 16.5, 12.0)
    _head(d, 2, 84, 88, 16.5, 12.0)
    _stem(d, 2, 44.5, 28, 96, 6.0)
    _stem(d, 2, 98.5, 18, 86, 6.0)
    _beam(d, 2, 41.5, 26, 101.5, 14, 12.0)
    # 3: two sixteenths on a double beam
    _head(d, 3, 30, 100, 16.5, 12.0)
    _head(d, 3, 84, 92, 16.5, 12.0)
    _stem(d, 3, 44.5, 24, 98, 6.0)
    _stem(d, 3, 98.5, 16, 90, 6.0)
    _beam(d, 3, 41.5, 22, 101.5, 12, 10.0)
    _beam(d, 3, 41.5, 40, 101.5, 30, 10.0)
    return m


def dilate(mask, px):
    out = mask
    for _ in range(int(round(px))):
        out = out.filter(ImageFilter.MaxFilter(3))
    return out


def main():
    mask = draw_mask()
    ring = dilate(mask, OUTLINE * SS)
    w, h = mask.size
    ink = Image.new("RGBA", (w, h), INK + (0,))
    ink.putalpha(ring)
    white = Image.new("RGBA", (w, h), FILL + (0,))
    white.putalpha(mask)
    big = Image.alpha_composite(ink, white)
    small = big.resize((CELL * CELLS, CELL), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    small.save(OUT)
    # a look at it on sand, for the eye
    sheet = Image.new("RGBA", small.size, (214, 180, 130, 255))
    sheet = Image.alpha_composite(sheet, small)
    review = os.path.join(ROOT, "tools", "dl", "review")
    os.makedirs(review, exist_ok=True)
    sheet.resize((small.width * 2, small.height * 2), Image.LANCZOS).save(os.path.join(review, "notes_atlas.png"))
    print("gen_notes: wrote %s (%dx%d) and tools/dl/review/notes_atlas.png" % (OUT, small.width, small.height))


if __name__ == "__main__":
    main()
