"""The two kind glyphs a card's plate carries in its bottom-left corner (pass 54, Garry: "a small corner glyph" telling
a weapon from a line, since both now take the same level colours): a revolver for a weapon, a rolled scroll with a
ribbon for a line. Ink (#241b14) on transparent, 64 px, drawn at 8x and scaled down so every edge is smooth;
WPlate draws them inside a paper disc with an ink ring (28 px across on a level-up card, 37 in the chest's reel, 74 on
its landed plate). The lead imports them (game/art/ui/wanted/kind_*.png).

Pass 56 (Garry: "Change the marker for a weapon ... It should be a single revolver and it should look a bit more
different from the scroll glyph"; answered: a solid revolver silhouette, the scroll stays as it is): the two crossed
pistols read as one dark blob at the card's size, much like the scroll. The weapon is now one revolver side on, barrel
to the right and tilted up 15 degrees, filled in ink: a round cylinder with two flutes cut out and a clear arc behind it,
a hammer, a trigger guard ring with its hole clear and a grip curving down and back. One connected shape, against the
scroll's hollow outlined box. A glyph whose pixels have not changed is not written again (the scroll keeps its import).

Pass 73 (lane CARDS; Garry: the line items are fortune-teller cards, "Update the symbol to be a Card instead of whatever
it is now"): the line's glyph is one card tilted 12 degrees with a bold star on its face (line()); the scroll is kept as
scroll(), drawn by nothing. The file keeps its name, kind_line.png (the kind is still "line" in the code).

    python tools/make_kind_glyphs.py [--preview <png>]
"""
import argparse
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "art", "ui", "wanted")
INK = (0x24, 0x1B, 0x14, 255)
PAPER = (0xF3, 0xE6, 0xC8, 255)
PX = 64
SS = 8               # supersampling
S = PX * SS          # the canvas we draw on
LINE = 4 * SS        # a 4 px line at 64 px
## The revolver's tilt: barrel up to the right (pass 56, the brief: "tilted up about 15 degrees"), and the clear arc that
## parts the cylinder's back edge from the frame (degrees clockwise from the barrel's way, PIL's arc).
TILT = 15.0
ARC = (150, 232)
## WPlate's corner disc (KIND_FRAC of the plate across; the glyph fills 78 % of the paper inside the ink ring) and the
## plates it sits on: a level-up card's 170 px, the chest reel's 210, the chest's landed 436.
KIND_FRAC = 0.26
GLYPH_FRAC = 0.78
PLATES = (("level-up card", 170), ("chest reel", 210), ("chest, landed", 436))


def _bezier(p0, c, p2, n=24):
    """A quadratic curve from p0 to p2 pulled towards c, as n + 1 points."""
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p2[1]))
    return out


def revolver() -> Image.Image:
    """One revolver side on, barrel to the right, filled in ink (pass 56). Drawn as a mask (255 ink, 0 cut out) in units
    of one 64-px pixel round the canvas's middle: barrel with its front sight and the ejector housing under it, the
    trigger guard ring, the frame, a clear arc behind the cylinder (its round back edge), the hammer, the grip down and
    back, then the cylinder over them with its two flutes cut out; turned TILT degrees and fitted."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    u = S / 64.0
    ox, oy = S * 0.5, S * 0.5

    def pt(x, y):
        return (ox + x * u, oy + y * u)

    def box(x0, y0, x1, y1, rad, fill=255):
        d.rounded_rectangle([ox + x0 * u, oy + y0 * u, ox + x1 * u, oy + y1 * u], radius=rad * u, fill=fill)

    def disc(cx, cy, r, fill=255):
        d.ellipse([ox + (cx - r) * u, oy + (cy - r) * u, ox + (cx + r) * u, oy + (cy + r) * u], fill=fill)

    cx, cy, cr = 0.5, -1.5, 9.4          # the cylinder: its middle sits under the barrel's line, as a real one's does
    # the barrel, its front sight, the ejector housing under it
    box(4.0, -7.5, 31.0, -0.5, 1.5)
    box(27.0, -10.3, 30.0, -6.5, 0.8)
    box(8.0, -1.6, 23.0, 3.1, 1.9)
    # the trigger guard: a ring under the frame, its hole clear
    disc(-1.5, 6.8, 5.8)
    disc(-1.5, 6.8, 5.8 - 2.3, fill=0)
    # the frame round the cylinder and behind it (over the guard's top)
    box(-13.5, -8.0, 7.0, 4.8, 3.0)
    # the grip: down and back in a curve (about 37 degrees back from the barrel's square, so it still rakes back once the
    # gun is tilted), its butt rounded and flaring back
    front = _bezier((-5.5, 3.5), (-9.0, 10.0), (-15.5, 17.0))
    back = _bezier((-26.0, 13.5), (-20.5, 5.5), (-14.5, -1.0))
    d.polygon([pt(*p) for p in front + back], fill=255)
    d.ellipse([ox - 26.8 * u, oy + 12.5 * u, ox - 15.2 * u, oy + 19.1 * u], fill=255)
    # the clear arc behind the cylinder: its round back edge against the frame; only the back (ARC degrees, clockwise from
    # the barrel's way), so the frame under the cylinder still joins the guard and the grip and the gun stays one shape
    gap = 2.2
    rr = cr + gap
    d.arc([ox + (cx - rr) * u, oy + (cy - rr) * u, ox + (cx + rr) * u, oy + (cy + rr) * u], ARC[0], ARC[1], fill=0,
          width=int(round(gap * u)))
    # the hammer: a wedge up and back from the frame's top, its nose against the cylinder, its spur rounded
    d.polygon([pt(-6.0, -7.2), pt(-15.8, -13.9), pt(-19.0, -11.7), pt(-14.5, -6.0)], fill=255)
    disc(-17.5, -12.9, 1.95)
    # the cylinder, round, standing over the barrel's line and under the frame, two flutes cut out of it (2.2 px: at the
    # card's 28 px wider flutes read as a hole in the gun, at the chest's 74 px these still show plainly)
    disc(cx, cy, cr)
    fh = 2.2
    for dy in (-2.8, 2.8):
        box(cx - 5.6, cy + dy - fh / 2, cx + 5.6, cy + dy + fh / 2, fh / 2, fill=0)
    m = m.rotate(TILT, resample=Image.BICUBIC, center=(S * 0.5, S * 0.5))
    im = Image.new("RGBA", (S, S), INK[:3] + (0,))
    im.putalpha(m)
    return im


def weapon() -> Image.Image:
    """The weapon's glyph: one revolver (pass 56; two crossed pistols in pass 54)."""
    return _fit(revolver())


def line() -> Image.Image:
    """The line items' glyph since pass 73 (lane CARDS; Garry: "Update the symbol to be a Card instead of whatever it is
    now"): one fortune card standing tilted CARD_TILT degrees clockwise, a thick ink outline with rounded corners round
    a paper face, and a bold four-pointed star in its middle, apart from the outline (two shapes: at the card plate's
    28 px it reads as a card, not as the revolver's one dark shape)."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    u = S / 64.0
    cx, cy = S * 0.5, S * 0.5
    hw, hh = 18.5 * u, 27.0 * u                  # half the card: 37 x 54 at 64 px, a tarot card's 2:3 or near it
    w = int(round(5.0 * u))                      # the outline: 5 px at 64, about 2 px at the card's 28
    d.rounded_rectangle([cx - hw, cy - hh, cx + hw, cy + hh], radius=6.0 * u, outline=255, width=w)
    # the star: four long points (the up and down ones longer, filling the tall face) and four short ones, solid ink, its
    # tips clear of the outline
    pts = []
    for k in range(16):
        ang = math.pi * k / 8.0 - math.pi / 2.0
        if k % 8 == 0:
            r = 15.5          # up, down
        elif k % 4 == 0:
            r = 10.5          # left, right: the face is narrower
        elif k % 2 == 0:
            r = 8.0           # the diagonals
        else:
            r = 6.4           # the valleys between: wide, so every point stays thick at 28 px
        pts.append((cx + r * u * math.cos(ang), cy + r * u * math.sin(ang)))
    d.polygon(pts, fill=255)
    m = m.rotate(-CARD_TILT, resample=Image.BICUBIC, center=(S * 0.5, S * 0.5))
    im = Image.new("RGBA", (S, S), INK[:3] + (0,))
    im.putalpha(m)
    return _fit(im)


## The card's tilt (pass 73): its top leans right, as the painted cards' B look stands.
CARD_TILT = 12.0


def scroll() -> Image.Image:
    """The line glyph from pass 54 to pass 72: a rolled scroll lying across, a roll at each end, three lines of writing,
    a ribbon tied round its middle (kept for the record; nothing draws it)."""
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = S / 64.0
    cx, cy = S * 0.5, S * 0.5
    w = LINE
    # the sheet between the rolls
    d.rectangle([cx - 21 * u, cy - 13 * u, cx + 21 * u, cy + 13 * u], outline=INK, width=w)
    # the two rolls: tall rounded ends with a spiral eye
    for sx in (-1, 1):
        x = cx + sx * 22 * u
        d.rounded_rectangle([x - 5.5 * u, cy - 17 * u, x + 5.5 * u, cy + 17 * u], radius=5.5 * u, outline=INK, width=w)
        d.ellipse([x - 2.2 * u, cy - 14.5 * u, x + 2.2 * u, cy - 10.1 * u], fill=INK)
    # the writing: three short lines, left of the ribbon and right of it
    for k, (a, b) in enumerate([(-15, -6), (-15, -8), (-15, -5)]):
        y = cy + (-6.5 + k * 6.5) * u
        d.line([cx + a * u, y, cx + b * u, y], fill=INK, width=int(2.4 * u))
        d.line([cx + (-a - 9 + (k % 2) * 2) * u, y, cx + (-b + 9) * u, y], fill=INK, width=int(2.4 * u))
    # the ribbon: a band round the middle and two tails hanging under it
    d.rectangle([cx - 3.2 * u, cy - 14.5 * u, cx + 3.2 * u, cy + 14.5 * u], fill=INK)
    d.polygon([(cx - 2 * u, cy + 12 * u), (cx - 9 * u, cy + 25 * u), (cx - 5 * u, cy + 23 * u), (cx - 3 * u, cy + 27 * u),
               (cx + 1.5 * u, cy + 13 * u)], fill=INK)
    d.polygon([(cx + 2 * u, cy + 12 * u), (cx + 9 * u, cy + 25 * u), (cx + 5 * u, cy + 23 * u), (cx + 3 * u, cy + 27 * u),
               (cx - 1.5 * u, cy + 13 * u)], fill=INK)
    return _fit(im)


def _fit(im: Image.Image) -> Image.Image:
    """Down to 64 px with a 2 px margin, the drawing centred on its own bounding box."""
    box = im.getbbox()
    if box:
        im = im.crop(box)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
    inner = PX - 4
    small = sq.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (PX, PX), (0, 0, 0, 0))
    out.alpha_composite(small, (2, 2))
    return out


def _same_pixels(a: Image.Image, path: str) -> bool:
    """Whether the PNG at `path` holds exactly these RGBA pixels."""
    if not os.path.exists(path):
        return False
    try:
        b = Image.open(path).convert("RGBA")
    except OSError:
        return False
    return b.size == a.size and b.tobytes() == a.convert("RGBA").tobytes()


# --- the preview ---------------------------------------------------------------------------------------------------

def _as_drawn(g: Image.Image, size: float) -> Image.Image:
    """The glyph drawn `size` px across the way a CanvasItem draws it in the game: bilinear, no mipmaps (the import
    makes none), so a 64 px glyph shrunk to 28 px skips texels instead of averaging them."""
    n = int(math.ceil(size))
    k = PX / size
    return g.transform((n, n), Image.AFFINE, (k, 0, 0, 0, k, 0), resample=Image.BILINEAR)


def _corner(g: Image.Image, side: int, fill, scale: int = 1) -> Image.Image:
    """A `side` px plate's bottom-left corner with WPlate's kind disc on it (WPlate.kind_disc / _kind_disc: KIND_FRAC of
    the plate across, 10 px past the border's inner edge, an ink ring round paper, a hard ink shadow, the glyph at
    GLYPH_FRAC of the paper), at `scale` times the game's size; at scale 1 the glyph is shrunk as the game shrinks it."""
    border = 4
    cw = int(side * 0.4) + 24
    ch = int(side * 0.4) + 24
    big = 4 * scale                        # the disc's own supersampling, for smooth circles
    lay = Image.new("RGBA", (cw * big, ch * big), PAPER)
    d = ImageDraw.Draw(lay)
    # the plate: its bottom-left corner 14 px in from the crop's left and bottom
    x0, y1 = 14, ch - 14

    def b(v):
        return v * big

    d.rounded_rectangle([b(x0), b(y1 - side), b(x0 + side), b(y1)], radius=b(10), fill=INK)
    d.rounded_rectangle([b(x0 + border), b(y1 - side + border), b(x0 + side - border), b(y1 - border)], radius=b(7),
                        fill=tuple(fill) + (255,))
    dd = round(side * KIND_FRAC)
    rad = dd * 0.5
    edge = max(round(rad * 0.16), 2)
    cx = x0 + border - 10.0 + rad
    cy = y1 - side + side - border + 10.0 - dd + rad
    sh = edge * 0.6
    d.ellipse([b(cx + sh - rad), b(cy + sh - rad), b(cx + sh + rad), b(cy + sh + rad)], fill=INK[:3] + (217,))
    d.ellipse([b(cx - rad), b(cy - rad), b(cx + rad), b(cy + rad)], fill=INK)
    d.ellipse([b(cx - rad + edge), b(cy - rad + edge), b(cx + rad - edge), b(cy + rad - edge)], fill=PAPER)
    out = lay.resize((cw * scale, ch * scale), Image.LANCZOS)
    inner = (rad - edge) * 2.0 * GLYPH_FRAC
    gi = _as_drawn(g, inner) if scale == 1 else g.resize((round(inner * scale), round(inner * scale)), Image.LANCZOS)
    out.alpha_composite(gi, (round((cx - inner * 0.5) * scale), round((cy - inner * 0.5) * scale)))
    return out


def preview(glyphs: dict, path: str) -> None:
    """A review sheet: each glyph at 4x on paper; in WPlate's paper disc at 4x (on a common plate and a legendary one);
    at the real size on a level-up card, the chest's reel and its landed plate, and the card's corner blown up 4x pixel
    for pixel, so what the eye gets at 28 px is plain."""
    pad = 24
    label_h = 16
    rows = []
    names = " and ".join(glyphs.keys())
    # 1. each glyph at 4x
    rows.append(("%s at 4x" % names, [g.resize((PX * 4, PX * 4), Image.LANCZOS) for g in glyphs.values()]))
    # 2. in the paper disc at 4x, on a common plate and a legendary one
    rows.append(("in WPlate's paper disc at 4x, on a common plate and a legendary one",
                 [_corner(g, 170, (0xD2, 0xCF, 0xC7), 4) for g in glyphs.values()]
                 + [_corner(g, 170, (0xE0, 0xA0, 0x60), 4) for g in glyphs.values()]))
    # 3. at the real size: the card, the reel and the landed plate
    rows.append(("real size: " + ", ".join("%s %d px" % (n, s) for n, s in PLATES),
                 [_corner(g, side, (0xD2, 0xCF, 0xC7)) for _, side in PLATES for g in glyphs.values()]))
    # 4. the card's corner at its real size blown up 4x pixel for pixel
    cards = [_corner(g, 170, (0xD2, 0xCF, 0xC7)) for g in glyphs.values()]
    rows.append(("the level-up card's corner at its real size, blown up 4x pixel for pixel",
                 [c.resize((c.size[0] * 4, c.size[1] * 4), Image.NEAREST) for c in cards]))
    width = max(sum(t.size[0] for t in r) + pad * (len(r) + 1) for _, r in rows)
    height = sum(max(t.size[1] for t in r) + label_h for _, r in rows) + pad * (len(rows) + 1)
    sheet = Image.new("RGBA", (width, height), PAPER)
    d = ImageDraw.Draw(sheet)
    y = pad
    for label, r in rows:
        d.text((pad, y), label, fill=INK)
        y += label_h
        x = pad
        for t in r:
            sheet.alpha_composite(t, (x, y))
            x += t.size[0] + pad
        y += max(t.size[1] for t in r) + pad
    sheet.save(path)
    print("preview", path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="", help="also write a review sheet of both glyphs: 4x, in the paper disc, "
                                                  "and at the real sizes on the cards and in the chest")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    glyphs = {"weapon": weapon(), "line": line()}
    for k, g in glyphs.items():
        path = os.path.join(OUT, "kind_%s.png" % k)
        if _same_pixels(g, path):
            print("unchanged", path)
            continue
        g.save(path)
        print("wrote", path)
    if a.preview:
        preview(glyphs, a.preview)


if __name__ == "__main__":
    main()
