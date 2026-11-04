"""The loading screen's saloon wallpaper and its title plate (pass 118, lane LOAD; Garry: "No icon, No progress bar.
Title Drop sequence at the start and an animation of silhuettes of revolvers, stars, bombs, boots and other western(y)
and not so western(y) item silhouettes that read well. They are meant to look like strips of saloon wallpaper and each
strip moves slowly up-and a bit to the right, down-and a bit to the right ... This is meant to be the new progress bar
replacement showing that the game is loading." Reference: _REFERENCES/2d/wallpapoer.jfif, a tone-on-tone western print).

Writes, for game/ui/Boot.gd (which draws all of it in one shader over the whole screen):

  game/art/ui/loading/wallpaper.png   the strip atlas: VARIANTS strips side by side, each STRIP_W canvas px wide and
                                      PERIOD canvas px tall (a vertical repeat), drawn at TEX_SCALE texels a canvas px.
                                      Masks, not colours: R = the silhouettes, G = the small fillers between them and the
                                      beads by the edges, B = the pinstripe at each edge. Boot.gd's shader colours them
                                      with the strip's ground (two tones, alternating), so the palette lives in one place.
  game/art/ui/loading/title_plate.png the game's name on a paper plate (the Wanted kit's: paper, an ink border, a hard ink
                                      shadow, brass nails), set like the title screen's logo: OUTLAW in Alfa Slab in ink
                                      with a hard brass shadow, SURVIVORS in Bitter 600 capitals tracked, at PLATE_SCALE.

Every silhouette is a mask in a 256 box: cut from one of the game's own icons (its alpha, small islands dropped, a hue
range dropped where the icon carries a trail, the edge smoothed) or drawn as clean vectors with PIL. Only the ones in
KEEP go on the wallpaper; the review sheet shows every candidate at the size a phone shows it, kept or not:

  tools/dl/p118/LOAD/silhouettes_review.png

  python tools/make_loading_wallpaper.py [--review-only] [--mock out.png [--h 2400]]
  python tools/make_loading_wallpaper.py --sheet tools/dl/p118/LOAD     (contact sheets of load_shots.gd captures)

--mock composes a still of the finished screen (the wallpaper at rest with the plate landed) to look at; the game's
own captures come from game/tools/load_shots.gd. No beer or bottles: Garry is taking the Beer out.
"""
import argparse
import math
import os
import random
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "game")
OUT_DIR = os.path.join(GAME, "art", "ui", "loading")
OUT_WALL = os.path.join(OUT_DIR, "wallpaper.png")
OUT_PLATE = os.path.join(OUT_DIR, "title_plate.png")
REVIEW = os.path.join(REPO, "tools", "dl", "p118", "LOAD", "silhouettes_review.png")
BOOT = os.path.join(GAME, "ui", "Boot.gd")
FONTS = os.path.join(GAME, "ui", "fonts")

# --- the strips (canvas px; Boot.gd reads the same numbers, written into it by write_boot_constants) ----------------
STRIP_W = 180          # six strips across the 1080 px canvas
PERIOD = 1440          # a strip's vertical repeat: ROWS motifs ROW_H apart
ROWS = 8
ROW_H = PERIOD // ROWS
VARIANTS = 4           # strips of different motif orders, side by side in the atlas
TEX_SCALE = 1.25       # texels a canvas px (a Pixel 8 Pro draws the 1080 px canvas 1344 px wide)
MOTIF = 104            # a motif's longest side, canvas px
SWAY = 18              # motifs sit this far left and right of the strip's middle, row by row (a stagger)
TILT = 9.0             # and lean up to this many degrees either way
ACCENT = 22            # the small fillers between the motifs (card suits, little stars), canvas px
PIN = 1.6              # the pinstripe at each edge, canvas px (two strips meet in a line twice as wide)
BEAD_X = 9.0           # the beads' line, this far in from each edge
BEAD_R = 1.7
BEAD_STEP = 12.0
SEED = 118

# --- the title plate (canvas px at 1.0; drawn at PLATE_SCALE) -----------------------------------------------------
PLATE_SCALE = 1.5
LOGO_PX = 158          # OUTLAW (the title screen sets it at 190 px; the plate keeps room round it on a 1080 px screen)
LOGO_SHADOW = 9
TAG_PX = 40            # SURVIVORS
TAG_TRACK = 0.3
PLATE_PAD_X = 46
PLATE_PAD_TOP = 40
PLATE_PAD_FOOT = 44
GAP_TAG = 26
BORDER = 7
SHADOW = 14            # the plate's hard ink shadow, down and right
NAIL_R = 9
PLATE_PAD = 4          # a clear margin round the plate (canvas px), so its edge is smoothed by the texture's filter

S = 4                  # vector silhouettes are drawn this much bigger and scaled down
BOX = 256


# ============================================================================ the kit's colours and words

def _w_src():
    return open(os.path.join(GAME, "ui", "wanted", "W.gd"), encoding="utf-8").read()


def w_color(name):
    m = re.search(r'^const %s := Color\("([0-9a-fA-F]{6})"\)' % name, _w_src(), re.M)
    if not m:
        raise SystemExit("W.gd has no %s" % name)
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def w_string(name):
    m = re.search(r'^const %s := "([^"]*)"' % name, _w_src(), re.M)
    if not m:
        raise SystemExit("W.gd has no %s" % name)
    return m.group(1)


# ============================================================================ vector drawing

class Pen:
    """An L mask drawn in a 256 box at S times the size: 255 adds, 0 knocks out."""

    def __init__(self):
        self.im = Image.new("L", (BOX * S, BOX * S), 0)
        self.d = ImageDraw.Draw(self.im)

    def poly(self, pts, v=255):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=v)

    def ell(self, cx, cy, rx, ry, v=255):
        self.d.ellipse(((cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S), fill=v)

    def circ(self, cx, cy, r, v=255):
        self.ell(cx, cy, r, r, v)

    def ring(self, cx, cy, r, w, v=0):
        self.d.ellipse(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S), outline=v, width=int(w * S))

    def rrect(self, x0, y0, x1, y1, r, v=255):
        self.d.rounded_rectangle((x0 * S, y0 * S, x1 * S, y1 * S), int(r * S), fill=v)

    def line(self, pts, w, v=255, caps=True):
        self.d.line([(x * S, y * S) for x, y in pts], fill=v, width=int(w * S), joint="curve")
        if caps:
            for x, y in (pts[0], pts[-1]):
                self.circ(x, y, w * 0.5, v)

    def text(self, cx, cy, s, px, v=0, path="AlfaSlabOne-Regular.ttf"):
        f = ImageFont.truetype(os.path.join(FONTS, path), int(px * S))
        self.d.text((cx * S, cy * S), s, font=f, fill=v, anchor="mm")

    def paste(self, other, deg=0.0, halo=0.0):
        """Another pen's drawing laid over this one, turned `deg` about the box's middle; `halo` px of gap round it."""
        im = other.im.rotate(deg, resample=Image.BICUBIC, center=(BOX * S / 2, BOX * S / 2)) if deg else other.im
        if halo > 0:
            grow = im.filter(ImageFilter.MaxFilter(int(halo * S) * 2 + 1))
            self.im.paste(0, (0, 0), grow)
        self.im.paste(255, (0, 0), im)

    def turned(self, deg):
        self.im = self.im.rotate(deg, resample=Image.BICUBIC, center=(BOX * S / 2, BOX * S / 2))
        self.d = ImageDraw.Draw(self.im)
        return self

    def mask(self):
        return self.im.resize((BOX, BOX), Image.LANCZOS)


def spline(pts, closed=True, n=10):
    """A Catmull-Rom curve through `pts`."""
    p = list(pts)
    out = []
    m = len(p)
    rng = range(m) if closed else range(m - 1)
    for i in rng:
        p0 = p[(i - 1) % m] if closed else p[max(i - 1, 0)]
        p1 = p[i]
        p2 = p[(i + 1) % m] if closed else p[i + 1]
        p3 = p[(i + 2) % m] if closed else p[min(i + 2, m - 1)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    if not closed:
        out.append(p[-1])
    return out


def taper(path, w0, w1):
    """A stroke along `path` whose width runs from w0 to w1: a closed polygon."""
    left, right = [], []
    n = len(path)
    for i, (x, y) in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = (w0 + (w1 - w0) * i / max(n - 1, 1)) * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def star_pts(cx, cy, r_out, r_in, points, rot=-90.0):
    out = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180.0 / points)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def arc_pts(cx, cy, rx, ry, a0, a1, n=48):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def spade(p, cx, cy, r, v=0):
    """A card spade: two lobes, a point up, a flared stem."""
    p.circ(cx - r * 0.55, cy + r * 0.12, r * 0.6, v)
    p.circ(cx + r * 0.55, cy + r * 0.12, r * 0.6, v)
    p.poly([(cx - r * 1.12, cy + r * 0.05), (cx, cy - r * 1.25), (cx + r * 1.12, cy + r * 0.05), (cx, cy + r * 0.5)], v)
    p.poly([(cx, cy + r * 0.2), (cx - r * 0.45, cy + r * 1.15), (cx + r * 0.45, cy + r * 1.15)], v)


def heart(p, cx, cy, r, v=255):
    p.circ(cx - r * 0.52, cy - r * 0.25, r * 0.58, v)
    p.circ(cx + r * 0.52, cy - r * 0.25, r * 0.58, v)
    p.poly([(cx - r * 1.08, cy - r * 0.1), (cx + r * 1.08, cy - r * 0.1), (cx, cy + r * 1.1)], v)


def club(p, cx, cy, r, v=255):
    for dx, dy in ((0, -0.55), (-0.58, 0.2), (0.58, 0.2)):
        p.circ(cx + dx * r, cy + dy * r, r * 0.5, v)
    p.circ(cx, cy, r * 0.3, v)
    p.poly([(cx, cy), (cx - r * 0.42, cy + r * 1.1), (cx + r * 0.42, cy + r * 1.1)], v)


def v_hat():
    p = Pen()
    crown = spline([(66, 142), (62, 104), (68, 70), (84, 44), (104, 32), (120, 40), (128, 54), (136, 40), (152, 32),
                    (172, 44), (188, 70), (194, 104), (190, 142)])
    p.poly(crown)
    p.line([(60, 118), (196, 118)], 10, 0, caps=False)
    brim = spline([(6, 98), (30, 124), (70, 138), (128, 142), (186, 138), (226, 124), (250, 98), (244, 118), (216, 146),
                   (172, 160), (128, 164), (84, 160), (40, 146), (12, 118)])
    p.poly(brim)
    return p


def v_horseshoe():
    p = Pen()
    path = arc_pts(128, 124, 74, 80, 124, 416, 64)
    p.line(path, 46)
    for a in (160, 196, 232, 308, 344, 380):
        x = 128 + 80 * math.cos(math.radians(a))
        y = 124 + 86 * math.sin(math.radians(a))
        p.circ(x, y, 5.5, 0)
    return p


def v_cactus():
    p = Pen()
    p.rrect(108, 26, 150, 238, 21)
    p.rrect(64, 132, 116, 156, 12)
    p.rrect(58, 74, 86, 156, 14)
    p.rrect(142, 108, 196, 130, 11)
    p.rrect(170, 48, 196, 130, 13)
    for x in (122, 136):
        p.line([(x, 42), (x, 226)], 3.2, 0)
    return p


def v_skull():
    p = Pen()
    left = spline([(96, 104), (66, 104), (36, 92), (18, 70), (12, 44)], closed=False, n=8)
    p.poly(taper(left, 30, 7))
    right = [(256 - x, y) for x, y in left]
    p.poly(taper(right, 30, 7))
    head = spline([(90, 88), (128, 82), (166, 88), (180, 108), (170, 142), (154, 170), (148, 206), (128, 228), (108, 206),
                   (102, 170), (86, 142), (76, 108)])
    p.poly(head)
    p.poly(spline([(94, 120), (116, 116), (122, 132), (112, 146), (98, 140)]), 0)
    p.poly(spline([(162, 120), (140, 116), (134, 132), (144, 146), (158, 140)]), 0)
    p.ell(120, 200, 4.5, 7, 0)
    p.ell(136, 200, 4.5, 7, 0)
    p.line([(128, 92), (124, 106), (130, 116)], 3, 0)
    return p


def v_dynamite():
    p = Pen()
    for cx, top in ((84, 104), (172, 104), (128, 90)):
        q = Pen()
        q.rrect(cx - 23, top, cx + 23, 236, 8)
        q.ell(cx, top + 4, 17, 5.5, 0)
        p.paste(q, halo=3.0)
    p.rrect(52, 152, 204, 180, 5, 0)
    p.rrect(56, 156, 200, 176, 4)
    p.line(spline([(128, 92), (134, 66), (156, 52), (170, 30)], closed=False, n=8), 7)
    p.poly(star_pts(174, 22, 22, 8, 8))
    return p


def v_spur():
    p = Pen()
    p.poly(star_pts(178, 118, 50, 20, 10))
    p.circ(178, 118, 15)
    p.circ(178, 118, 6, 0)
    p.line([(96, 118), (166, 118)], 14)
    p.line(arc_pts(70, 118, 46, 56, -78, 78, 32), 18)
    for a in (-78, 78):
        x = 70 + 46 * math.cos(math.radians(a))
        y = 118 + 56 * math.sin(math.radians(a))
        p.circ(x, y, 12)
    p.line(spline([(84, 176), (100, 204), (130, 214), (160, 204)], closed=False, n=8), 7)
    return p


def v_cards():
    p = Pen()
    back = Pen()
    back.rrect(84, 42, 190, 196, 14)
    back.turned(-14)
    p.paste(back)
    front = Pen()
    front.rrect(58, 60, 164, 214, 14)
    spade(front, 111, 128, 28, 0)
    front.text(76, 82, "A", 26, 0)
    front.turned(10)
    p.paste(front, halo=5.0)
    return p


def v_dice():
    p = Pen()
    a = Pen()
    a.rrect(36, 98, 140, 202, 18)
    for dx, dy in ((-28, -28), (28, -28), (0, 0), (-28, 28), (28, 28)):
        a.circ(88 + dx, 150 + dy, 10, 0)
    a.turned(14)
    p.paste(a)
    b = Pen()
    b.rrect(124, 42, 220, 138, 18)
    for dx, dy in ((-24, -24), (0, 0), (24, 24)):
        b.circ(172 + dx, 90 + dy, 9.5, 0)
    b.turned(-16)
    p.paste(b, halo=6.0)
    return p


def v_coin():
    p = Pen()
    p.circ(128, 128, 98)
    p.ring(128, 128, 84, 5, 0)
    p.text(128, 136, "$", 136, 0)
    return p


def v_lasso():
    p = Pen()
    q = Pen()
    q.d.ellipse((30 * S, 40 * S, 226 * S, 170 * S), outline=255, width=21 * S)
    for i in range(18):
        a = math.radians(i * 20 + 6)
        x, y = 128 + 87.5 * math.cos(a), 105 + 54.5 * math.sin(a)
        q.line([(x - 5, y - 7), (x + 5, y + 7)], 2.6, 0, caps=False)
    q.turned(-8)
    p.paste(q)
    p.ell(178, 160, 18, 14)
    p.line(spline([(178, 168), (196, 196), (180, 222), (152, 232), (134, 248)], closed=False, n=10), 16)
    return p


def v_bomb():
    p = Pen()
    p.circ(116, 152, 80)
    cap = Pen()
    cap.rrect(150, 64, 190, 92, 6)
    cap.turned(-40)
    p.paste(cap)
    p.line(spline([(180, 72), (200, 52), (198, 34), (214, 20)], closed=False, n=8), 8)
    p.poly(star_pts(220, 16, 22, 8, 8))
    p.line(arc_pts(116, 152, 54, 54, 196, 248, 16), 11, 0)
    return p


def v_star():
    p = Pen()
    pts = star_pts(128, 132, 108, 54, 6)
    p.poly(pts)
    for x, y in pts[::2]:
        p.circ(x, y, 14)
    p.ring(128, 132, 42, 6, 0)
    p.poly(star_pts(128, 132, 24, 11, 5), 0)
    return p


def v_boot():
    p = Pen()
    pts = spline([(72, 18), (82, 14), (96, 22), (112, 28), (130, 22), (144, 12), (154, 16), (154, 70), (152, 122),
                  (162, 146), (192, 162), (226, 176), (246, 190), (250, 204), (238, 210), (132, 210), (122, 214),
                  (118, 240), (82, 240), (76, 214), (68, 178), (64, 120), (66, 64)])
    p.poly(pts)
    p.line([(134, 206), (244, 204)], 3.5, 0, caps=False)
    p.line(spline([(84, 58), (110, 74), (138, 58)], closed=False, n=8), 4, 0)
    p.line(spline([(82, 94), (110, 112), (140, 94)], closed=False, n=8), 4, 0)
    p.poly(star_pts(48, 206, 22, 9, 8))
    p.line([(48, 206), (72, 206)], 7)
    return p


def v_basketball():
    p = Pen()
    p.circ(128, 128, 100)
    seams = Pen()
    seams.line([(128, 20), (128, 236)], 7)
    seams.line([(20, 128), (236, 128)], 7)
    seams.line(arc_pts(-20, 128, 104, 104, -62, 62, 32), 7)
    seams.line(arc_pts(276, 128, 104, 104, 118, 242, 32), 7)
    p.im.paste(0, (0, 0), seams.im)
    p.turned(-18)
    return p


def v_frisbee():
    p = Pen()
    p.ell(128, 140, 110, 44)
    p.ell(128, 128, 110, 44)
    p.d.arc(((128 - 110) * S, (128 - 44) * S, (128 + 110) * S, (128 + 44) * S), 8, 172, fill=0, width=5 * S)
    p.d.ellipse(((128 - 72) * S, (128 - 28) * S, (128 + 72) * S, (128 + 28) * S), outline=0, width=5 * S)
    p.turned(16)
    return p


def v_rocket():
    p = Pen()
    body = spline([(128, 14), (150, 44), (160, 92), (158, 168), (146, 188), (110, 188), (98, 168), (96, 92), (106, 44)])
    p.poly(body)
    for sgn in (-1, 1):
        p.poly([(128 + sgn * 28, 132), (128 + sgn * 62, 186), (128 + sgn * 62, 212), (128 + sgn * 28, 186)])
    p.circ(128, 94, 17, 0)
    p.circ(128, 94, 10)
    p.line([(98, 162), (158, 162)], 4, 0, caps=False)
    p.poly([(110, 196), (128, 246), (146, 196)])
    p.line([(108, 194), (148, 194)], 4, 0, caps=False)
    p.turned(-38)
    return p


def v_salt():
    p = Pen()
    p.poly([(82, 104), (174, 104), (186, 214), (180, 226), (76, 226), (70, 214)])
    p.ell(128, 74, 44, 34)
    p.rrect(84, 70, 172, 102, 6)
    p.line([(80, 104), (176, 104)], 5, 0, caps=False)
    for x, y in ((112, 60), (128, 54), (144, 60), (120, 76), (136, 76)):
        p.circ(x, y, 4.5, 0)
    for x in (108, 128, 148):
        p.line([(x, 120), (x + (x - 128) * 0.08, 212)], 3.2, 0, caps=False)
    return p


def v_wheel():
    p = Pen()
    p.circ(128, 128, 106)
    p.circ(128, 128, 86, 0)
    for i in range(10):
        a = math.radians(i * 36)
        p.line([(128 + 18 * math.cos(a), 128 + 18 * math.sin(a)), (128 + 90 * math.cos(a), 128 + 90 * math.sin(a))], 11,
               caps=False)
    p.circ(128, 128, 26)
    p.circ(128, 128, 8, 0)
    return p


def v_lantern():
    p = Pen()
    p.d.arc(((128 - 30) * S, (44 - 30) * S, (128 + 30) * S, (44 + 30) * S), 180, 360, fill=255, width=8 * S)
    p.poly([(96, 46), (160, 46), (176, 78), (80, 78)])
    p.ell(128, 138, 54, 62)
    p.rrect(82, 188, 174, 226, 10)
    p.line([(82, 190), (174, 190)], 4, 0, caps=False)
    for x in (80, 176):
        p.line([(x, 80), (x, 192)], 8)
    flame = spline([(128, 98), (144, 128), (146, 152), (128, 168), (110, 152), (112, 128)])
    p.poly(flame, 0)
    return p


def v_bullets():
    p = Pen()
    for cx, top in ((84, 74), (128, 52), (172, 74)):
        p.rrect(cx - 18, top + 50, cx + 18, 222, 4)
        p.poly(spline([(cx - 18, top + 50), (cx - 16, top + 20), (cx, top), (cx + 16, top + 20), (cx + 18, top + 50)],
                      closed=False, n=8) + [(cx + 18, top + 52), (cx - 18, top + 52)])
        p.line([(cx - 20, top + 54), (cx + 20, top + 54)], 4, 0, caps=False)
        p.rrect(cx - 21, 214, cx + 21, 228, 3)
        p.line([(cx - 22, 212), (cx + 22, 212)], 3, 0, caps=False)
    return p


def v_moneybag():
    p = Pen()
    body = spline([(108, 74), (148, 74), (190, 120), (204, 176), (186, 222), (128, 236), (70, 222), (52, 176), (66, 120)])
    p.poly(body)
    p.poly([(100, 66), (114, 40), (128, 54), (142, 40), (156, 66)])
    p.line([(100, 72), (156, 72)], 9, 0, caps=False)
    p.rrect(98, 64, 158, 80, 6)
    p.text(128, 162, "$", 92, 0)
    return p


# accents: small fillers between motifs
def a_spade():
    p = Pen()
    spade(p, 128, 120, 80, 255)
    return p


def a_heart():
    p = Pen()
    heart(p, 128, 128, 96)
    return p


def a_club():
    p = Pen()
    club(p, 128, 118, 110)
    return p


def a_diamond():
    p = Pen()
    p.poly([(128, 16), (204, 128), (128, 240), (52, 128)])
    return p


def a_star():
    p = Pen()
    p.poly(star_pts(128, 136, 118, 48, 5))
    return p


def a_sparkle():
    p = Pen()
    p.poly(star_pts(128, 128, 118, 26, 4, rot=-90))
    return p


VECTORS = {
    "hat": v_hat, "horseshoe": v_horseshoe, "cactus": v_cactus, "cow_skull": v_skull, "dynamite": v_dynamite,
    "spur": v_spur, "cards": v_cards, "dice": v_dice, "coin": v_coin, "lasso": v_lasso, "bomb": v_bomb,
    "star": v_star, "boot": v_boot, "basketball": v_basketball, "frisbee": v_frisbee, "rocket": v_rocket,
    "salt_shaker": v_salt, "wagon_wheel": v_wheel, "lantern": v_lantern, "bullets": v_bullets, "money_bag": v_moneybag,
}
ACCENTS = {"spade": a_spade, "heart": a_heart, "club": a_club, "diamond": a_diamond, "small_star": a_star,
           "sparkle": a_sparkle}

# ============================================================================ silhouettes from the game's icons

# id: (icon path under game/, options). "drop" removes a hue band (degrees, min saturation) the icon uses for a trail
# or a glow that is not the object; "flip" mirrors it; "turn" turns it (degrees, counter-clockwise).
ICONS = {
    "revolver": ("content/weapons/revolver/revolver_icon.png", {}),
    "tin_star": ("content/passives/tin_star/tin_star_icon.png", {}),
    "boot_icon": ("content/passives/evade/evade_icon.png", {"drop": (60, 170, 0.25)}),
    "guitar": ("content/weapons/guitarra/guitarra_icon.png", {}),
    "tommy_gun": ("content/weapons/tommy_gun/tommy_gun_icon.png", {}),
    "chicago": ("content/evolutions/chicago_typewriter/chicago_typewriter_icon.png", {}),
    "gravity_gun": ("content/weapons/gravity_gun/gravity_gun_icon.png", {}),
    "singularity": ("content/evolutions/singularity/singularity_icon.png", {}),
    "sun_sceptre": ("content/weapons/sun_scepter/sun_scepter_icon.png", {}),
    "saw_blade": ("content/weapons/orbit_saws/orbit_saws_icon.png", {}),
    "saw_halo": ("content/evolutions/saw_halo/saw_halo_icon.png", {}),
    "hammer": ("content/weapons/hammer/hammer_icon.png", {}),
    "sabre": ("content/weapons/sabre/sabre_icon.png", {}),
    "lightning": ("content/weapons/zap_beam/zap_beam_icon.png", {}),
    "clover": ("content/passives/clover/clover_icon.png", {}),
    "feather": ("content/passives/phoenix_feather/phoenix_feather_icon.png", {}),
    "chili": ("content/passives/ghost_pepper/ghost_pepper_icon.png", {}),
    "kettlebell": ("content/passives/heavyweight/heavyweight_icon.png", {}),
    "horse": ("content/passives/bucking_bronco/bucking_bronco_icon.png", {}),
    "gold_tooth": ("content/passives/gold_tooth/gold_tooth_icon.png", {}),
    "magnet": ("content/passives/magnet/magnet_icon.png", {}),
    "grenade": ("content/weapons/lob_grenade/lob_grenade_icon.png", {}),
    "frisbee_icon": ("content/weapons/frisbee/frisbee_icon.png", {}),
    "salt_icon": ("content/weapons/salt/salt_icon.png", {}),
    "barrel": ("content/passives/barrel_rush/barrel_rush_icon.png", {}),
    "handcuffs": ("content/passives/shackles/shackles_icon.png", {}),
    "bullets_icon": ("content/passives/multishot/multishot_icon.png", {}),
    "halberd": ("content/evolutions/halberd/halberd_icon.png", {}),
    "sword": ("content/evolutions/zweihander/zweihander_icon.png", {}),
    "pocket_watch": ("content/passives/pocket_watch/pocket_watch_icon.png", {}),
    "money_bag_icon": ("content/passives/hush_money/hush_money_icon.png", {}),
    "quickdraw": ("content/passives/quickdraw/quickdraw_icon.png", {}),
    "requiem": ("content/evolutions/requiem/requiem_icon.png", {}),
    "slam_dunk": ("content/evolutions/slam_dunk/slam_dunk_icon.png", {}),
}

# What goes on the wallpaper (picked from the review sheet by eye at phone size; see tools/dl/p118/LOAD/STATUS.md).
KEEP = [
    "revolver", "tin_star", "bomb", "boot", "hat", "horseshoe", "cactus", "cow_skull", "dynamite", "cards", "dice",
    "coin", "lasso", "money_bag", "wagon_wheel", "lantern", "bullets", "star", "chili", "basketball", "frisbee",
    "tommy_gun", "guitar", "salt_shaker", "rocket", "saw_blade", "gravity_gun", "sun_sceptre",
]
# Garry named these first ("revolvers, stars, bombs, boots"): they come twice as often, never twice in one strip.
TWICE = ["revolver", "tin_star", "bomb", "boot"]
ACCENT_KEEP = ["spade", "heart", "club", "diamond", "small_star", "sparkle"]


def icon_mask(rel, opts):
    im = Image.open(os.path.join(GAME, rel)).convert("RGBA")
    if opts.get("flip"):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(im, dtype=np.float32)
    alpha = a[..., 3] / 255.0
    if "drop" in opts:
        lo, hi, smin = opts["drop"]
        hsv = np.asarray(im.convert("RGB").convert("HSV"), dtype=np.float32)
        hue = hsv[..., 0] * 360.0 / 255.0
        sat = hsv[..., 1] / 255.0
        alpha = np.where((hue >= lo) & (hue <= hi) & (sat >= smin), 0.0, alpha)
    solid = alpha > 0.5
    # small islands (sparkles, a stray trail) go: keep pieces at least 4 % of the largest
    lab, n = ndimage.label(solid)
    if n > 1:
        sizes = ndimage.sum(solid, lab, range(1, n + 1))
        keep = np.zeros(n + 1, bool)
        keep[1:] = sizes >= sizes.max() * 0.04
        solid = keep[lab]
    # a smooth edge: up, blurred, cut at the middle, down
    big = Image.fromarray((solid * 255).astype(np.uint8)).resize((BOX * S, BOX * S), Image.BILINEAR)
    big = big.filter(ImageFilter.GaussianBlur(S * 1.1)).point(lambda v: 255 if v >= 128 else 0)
    if opts.get("turn"):
        big = big.rotate(opts["turn"], resample=Image.BICUBIC)
    return big.resize((BOX, BOX), Image.LANCZOS)


def fit(mask, side=BOX, margin=0.04):
    """The mask cropped to its ink and fitted in a `side` box, longest side (1 - 2 margin) of it, centred."""
    bb = mask.getbbox()
    if not bb:
        return Image.new("L", (side, side), 0)
    m = mask.crop(bb)
    k = side * (1 - 2 * margin) / max(m.size)
    m = m.resize((max(1, round(m.width * k)), max(1, round(m.height * k))), Image.LANCZOS)
    out = Image.new("L", (side, side), 0)
    out.paste(m, ((side - m.width) // 2, (side - m.height) // 2))
    return out


def silhouettes():
    out = {}
    for k, f in VECTORS.items():
        out[k] = ("vector", fit(f().mask()))
    for k, (rel, opts) in ICONS.items():
        if os.path.exists(os.path.join(GAME, rel)):
            out[k] = ("icon", fit(icon_mask(rel, opts)))
    return out


def accents():
    return {k: fit(f().mask(), margin=0.02) for k, f in ACCENTS.items()}


# ============================================================================ palette (mirrors Boot.gd's uniforms)

def palette():
    """The colours Boot.gd's shader gives the masks (pass 124: the dark wallpaper; Boot.gd's palette() holds the same)."""
    c = lambda h: np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)
    return {"paper": c("0b1020"), "ground_a": c("121a34"), "ground_b": c("182242"), "motif": c("26335f"), "accent": c("212c54"),
            "line": c("34416f"), "vignette": c("05070f")}


VIGNETTE = 0.5        # Boot.gd's VIGNETTE: how much of the warm shade the corners take


# ============================================================================ the review sheet

def review(sils, accs):
    pal = palette()
    phone = 1344 / 1080.0              # a Pixel 8 Pro's px per canvas px
    small = round(MOTIF * phone)       # what a phone shows
    cell_w, cell_h = 360, small + 300
    names = sorted(sils.keys(), key=lambda k: (k not in KEEP, k))
    cols = 6
    rows = (len(names) + cols - 1) // cols
    head = 90
    sheet = Image.new("RGB", (cols * cell_w, head + rows * cell_h + 220), tuple(int(v) for v in pal["paper"]))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(os.path.join(FONTS, "Bitter.ttf"), 22)
    fb = ImageFont.truetype(os.path.join(FONTS, "AlfaSlabOne-Regular.ttf"), 30)
    d.text((20, 20), "Loading wallpaper silhouettes: big, then at phone size on both strip tones. Green tick = kept (KEEP).",
           font=fb, fill=(36, 27, 20))
    for i, name in enumerate(names):
        kind, m = sils[name]
        x0 = (i % cols) * cell_w
        y0 = head + (i // cols) * cell_h
        big = m.resize((170, 170), Image.LANCZOS)
        ink = Image.new("RGB", big.size, (36, 27, 20))
        sheet.paste(ink, (x0 + 10, y0 + 10), big)
        # one at phone size over the two grounds side by side
        bg = Image.new("RGB", (small * 2 + 30, small + 20), tuple(int(v) for v in pal["ground_a"]))
        ImageDraw.Draw(bg).rectangle((small + 15, 0, small * 2 + 30, small + 20), fill=tuple(int(v) for v in pal["ground_b"]))
        sm = m.resize((small, small), Image.LANCZOS)
        col = Image.new("RGB", sm.size, tuple(int(v) for v in pal["motif"]))
        bg.paste(col, (5, 10), sm)
        bg.paste(col, (small + 25, 10), sm)
        sheet.paste(bg, (x0 + 10, y0 + 190))
        kept = name in KEEP
        d.text((x0 + 190, y0 + 20), name, font=f, fill=(36, 27, 20))
        d.text((x0 + 190, y0 + 48), kind, font=f, fill=(90, 74, 58))
        if kept:
            d.text((x0 + 190, y0 + 80), "KEPT", font=fb, fill=(70, 120, 60))
    # the accents
    ya = head + rows * cell_h + 20
    d.text((20, ya), "Fillers between the motifs (ACCENT_KEEP):", font=f, fill=(36, 27, 20))
    for i, (k, m) in enumerate(accs.items()):
        sm = m.resize((round(ACCENT * phone), round(ACCENT * phone)), Image.LANCZOS)
        big = m.resize((90, 90), Image.LANCZOS)
        x = 20 + i * 200
        sheet.paste(Image.new("RGB", big.size, (36, 27, 20)), (x, ya + 40), big)
        sheet.paste(Image.new("RGB", sm.size, tuple(int(v) for v in pal["accent"])), (x + 110, ya + 70), sm)
        d.text((x, ya + 140), k + (" (kept)" if k in ACCENT_KEEP else ""), font=f, fill=(36, 27, 20))
    os.makedirs(os.path.dirname(REVIEW), exist_ok=True)
    sheet.save(REVIEW)
    print("review: %s (%d silhouettes, %d kept)" % (REVIEW, len(names), len([n for n in names if n in KEEP])))


# ============================================================================ the strips

def strips(sils, accs):
    """The atlas: VARIANTS strips side by side; R silhouettes, G fillers and beads, B pinstripes."""
    rnd = random.Random(SEED)
    keep = [k for k in KEEP if k in sils]
    missing = [k for k in KEEP if k not in sils]
    if missing:
        raise SystemExit("make_loading_wallpaper: KEEP names %s, which are not drawn" % missing)
    slots = VARIANTS * ROWS
    pool = keep + [k for k in TWICE if k in keep]
    while len(pool) < slots:
        pool += keep
    pool = pool[:slots]
    for _ in range(10000):
        rnd.shuffle(pool)
        rows = [pool[v * ROWS:(v + 1) * ROWS] for v in range(VARIANTS)]
        if all(len(set(r)) == len(r) for r in rows):
            break
    else:
        raise SystemExit("make_loading_wallpaper: no order without a motif twice in one strip")
    order = pool
    tw, th = round(STRIP_W * TEX_SCALE), round(PERIOD * TEX_SCALE)
    R = np.zeros((th, tw * VARIANTS), np.float32)
    G = np.zeros_like(R)
    B = np.zeros_like(R)
    acc_names = [k for k in ACCENT_KEEP if k in accs]
    msize = round(MOTIF * TEX_SCALE)
    asize = round(ACCENT * TEX_SCALE)

    def stamp(layer, mask, cx, cy, deg, size, wrap_h):
        m = mask.resize((size, size), Image.LANCZOS)
        if deg:
            m = m.rotate(deg, resample=Image.BICUBIC, expand=True)
        arr = np.asarray(m, np.float32) / 255.0
        h, w = arr.shape
        x0 = round(cx - w / 2)
        y0 = round(cy - h / 2)
        for dy in (-wrap_h, 0, wrap_h):   # wrap vertically, so the strip repeats without a seam
            ys, xs = y0 + dy, x0
            a0, a1 = max(0, -ys), min(h, th - ys)
            if a1 <= a0:
                continue
            sub = layer[ys + a0:ys + a1, xs:xs + w]
            np.maximum(sub, arr[a0:a1, :sub.shape[1]], out=sub)

    for v in range(VARIANTS):
        ox = v * tw
        for r in range(ROWS):
            name = order[v * ROWS + r]
            side = -1 if (r + v) % 2 == 0 else 1
            cx = ox + (STRIP_W / 2 + side * SWAY) * TEX_SCALE
            cy = (r + 0.5) * ROW_H * TEX_SCALE
            deg = rnd.uniform(-TILT, TILT)
            stamp(R[:, ox:ox + tw], sils[name][1], cx - ox, cy, deg, msize, th)
            a = acc_names[(v * 3 + r) % len(acc_names)]
            acx = (STRIP_W / 2 - side * 46) * TEX_SCALE
            acy = (r + 1.0) * ROW_H * TEX_SCALE
            stamp(G[:, ox:ox + tw], accs[a], acx, acy % th, 0.0, asize, th)
        # the beads by each edge (they ride with the strip) and the pinstripe on each edge, drawn big and scaled down
        big = Image.new("L", (tw * S, th * S), 0)
        bd = ImageDraw.Draw(big)
        n = int(PERIOD / BEAD_STEP)
        for i in range(n):
            y = (i + 0.5) * BEAD_STEP * TEX_SCALE * S
            for bx in (BEAD_X, STRIP_W - BEAD_X):
                x = bx * TEX_SCALE * S
                rr = BEAD_R * TEX_SCALE * S
                bd.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
        beads = np.asarray(big.resize((tw, th), Image.LANCZOS), np.float32) / 255.0
        G[:, ox:ox + tw] = np.maximum(G[:, ox:ox + tw], beads)
        big = Image.new("L", (tw * S, th * S), 0)
        bd = ImageDraw.Draw(big)
        pw = PIN * TEX_SCALE * S
        bd.rectangle((0, 0, pw, th * S), fill=255)
        bd.rectangle((tw * S - pw, 0, tw * S, th * S), fill=255)
        B[:, ox:ox + tw] = np.asarray(big.resize((tw, th), Image.LANCZOS), np.float32) / 255.0
    rgb = np.stack([R, G, B], axis=-1)
    img = Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    os.makedirs(OUT_DIR, exist_ok=True)
    img.save(OUT_WALL, optimize=True)
    print("wallpaper: %s %dx%d %d KB (%d variants of %d rows, %d motifs)" % (
        OUT_WALL, img.width, img.height, os.path.getsize(OUT_WALL) // 1024, VARIANTS, ROWS, len(keep)))
    return img


# ============================================================================ the title plate

def tracked(d, text, font, track, x_left, baseline, fill):
    x = x_left
    for ch in text:
        d.text((x, baseline), ch, font=font, fill=fill, anchor="ls")
        x += font.getlength(ch) + track


def tracked_width(text, font, track):
    return sum(font.getlength(ch) for ch in text) + track * (len(text) - 1)


def plate():
    """Pass 124 (Garry: "use the new design of the Logo"): the main menu's wordmark on nothing: OUTLAW in Ultra, cream with the navy edge
    and drop (ui/TitleScreen.gd's RY_LOGO_*), the gold star line under it. The shader slams it in as it did the paper plate."""
    k = PLATE_SCALE
    cream, navy, gold = (255, 246, 220), (14, 31, 74), (255, 220, 115)
    ultra = os.path.join(FONTS, "Ultra-Regular.ttf")
    slab = ImageFont.truetype(ultra, round(LOGO_PX * k))
    tagf = ImageFont.truetype(ultra, round(TAG_PX * k))
    word, line = w_string("GAME_WORD").upper(), w_string("GAME_LINE").upper()
    edge = round(7 * k)
    drop = round(11 * k)
    d0 = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    l, t_, r, b = d0.textbbox((0, 0), word, font=slab, stroke_width=edge)
    ww, wh = r - l, b - t_
    track = round(TAG_PX * TAG_TRACK * k)
    tw = tracked_width(line, tagf, track)
    tl, tt, tr, tb = d0.textbbox((0, 0), "SURVIVORS", font=tagf, anchor="ls")
    th = tb - tt
    star_room = 96 * k
    pad = round(PLATE_PAD * k)
    pw = round(max(ww, tw + 2 * star_room)) + 2 * pad
    ph = round(wh + drop + GAP_TAG * k + th + round(5 * k) + round(3 * k)) + 2 * pad
    img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = pw / 2
    x = cx - ww / 2 - l
    y = pad - t_
    d.text((x, y + drop), word, font=slab, fill=navy + (255,), stroke_width=edge, stroke_fill=navy + (255,))
    d.text((x, y), word, font=slab, fill=cream + (255,), stroke_width=edge, stroke_fill=navy + (255,))
    base = pad + wh + drop + GAP_TAG * k - tt
    tag_edge = round(3 * k)
    # the line's drop and edge first, then its letters
    tx = cx - tw / 2
    for ch in line:
        d.text((tx, base + round(3 * k)), ch, font=tagf, fill=navy + (255,), anchor="ls", stroke_width=tag_edge, stroke_fill=navy + (255,))
        d.text((tx, base), ch, font=tagf, fill=gold + (255,), anchor="ls", stroke_width=tag_edge, stroke_fill=navy + (255,))
        tx += tagf.getlength(ch) + track
    mid_y = base + tt + th / 2
    for sgn in (-1, 1):
        sx = cx + sgn * (tw / 2 + 52 * k)
        d.polygon(star_pts(sx, mid_y + 2 * k, 21 * k, 9.5 * k, 5), fill=navy + (255,))
        d.polygon(star_pts(sx, mid_y, 16 * k, 7 * k, 5), fill=gold + (255,))
    img.save(OUT_PLATE, optimize=True)
    print("plate: %s %dx%d (%.1f x %.1f canvas px) %d KB" % (OUT_PLATE, img.width, img.height, img.width / k, img.height / k, os.path.getsize(OUT_PLATE) // 1024))
    return img


def write_boot_constants(wall, plate_img):
    """Boot.gd lays the atlas out with these numbers: written here so the two never drift apart."""
    src = open(BOOT, "rb").read().decode("utf-8")
    lines = {
        r"^const STRIP_W := [0-9.]+": "const STRIP_W := %.1f" % STRIP_W,
        r"^const PERIOD := [0-9.]+": "const PERIOD := %.1f" % PERIOD,
        r"^const VARIANTS := [0-9]+": "const VARIANTS := %d" % VARIANTS,
        r"^const PLATE_SIZE := Vector2\([^)]*\)": "const PLATE_SIZE := Vector2(%.1f, %.1f)" % (
            plate_img.width / PLATE_SCALE, plate_img.height / PLATE_SCALE),
        r"^const PLATE_SHADOW := [0-9.]+": "const PLATE_SHADOW := %.1f" % SHADOW,
    }
    new = src
    for pattern, line in lines.items():
        new, n = re.subn(pattern, line, new, flags=re.M)
        if n != 1:
            raise SystemExit("Boot.gd has no single `%s` line to write" % line.split(" := ")[0])
    if new != src:
        open(BOOT, "wb").write(new.encode("utf-8"))
        print("Boot.gd: STRIP_W %d, PERIOD %d, VARIANTS %d, PLATE_SIZE %.1f x %.1f" % (
            STRIP_W, PERIOD, VARIANTS, plate_img.width / PLATE_SCALE, plate_img.height / PLATE_SCALE))


# ============================================================================ a still to look at

def mock(path, h, wall, plate_img):
    """The finished screen at rest: what Boot.gd's shader draws once the plate has landed (to look at, not shipped)."""
    pal = palette()
    W_ = 1080
    a = np.asarray(wall, np.float32) / 255.0
    tw = round(STRIP_W * TEX_SCALE)
    out = np.zeros((h, W_, 3), np.float32)
    ys = np.arange(h, dtype=np.float32)
    for sx in range(0, W_, STRIP_W):
        idx = sx // STRIP_W
        v = idx % VARIANTS
        phase = (idx * 0.618034 % 1.0) * PERIOD
        ty = (((ys + phase) % PERIOD) * TEX_SCALE).astype(int).clip(0, a.shape[0] - 1)
        for x in range(sx, min(sx + STRIP_W, W_)):
            tx = min(int((x - sx) * TEX_SCALE), tw - 1) + v * tw
            col = a[ty, tx]
            g = pal["ground_a"] if idx % 2 == 0 else pal["ground_b"]
            c = np.tile(g, (h, 1))
            c = c + (pal["motif"] - c) * col[:, 0:1]
            c = c + (pal["accent"] - c) * col[:, 1:2]
            c = c + (pal["line"] - c) * col[:, 2:3]
            out[:, x] = c
    yy, xx = np.mgrid[0:h, 0:W_].astype(np.float32)
    r = np.sqrt(((xx - W_ / 2) / (W_ / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    e = np.clip((r - 0.55) / (1.35 - 0.55), 0, 1)
    e = e * e * (3 - 2 * e) * VIGNETTE
    out = out + (pal["vignette"] - out) * e[..., None]
    img = Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    p = plate_img.resize((round(plate_img.width / PLATE_SCALE), round(plate_img.height / PLATE_SCALE)), Image.LANCZOS)
    img.alpha_composite(p, ((W_ - p.width) // 2, round(h * 0.46 - p.height / 2)))
    img.convert("RGB").save(path)
    print("mock: %s" % path)


# ============================================================================ the captures' contact sheet

def measure_motion(a, b, ra, rb, top, bottom):
    """How far each strip moved between two captures (canvas px): for every strip whole on screen in both, a band of it
    in frame a is matched against frame b (shifted right by the drift between them) over vertical shifts."""
    ga = np.asarray(a.convert("L"), np.float32)
    gb = np.asarray(b.convert("L"), np.float32)
    drift = rb["drift"] - ra["drift"]
    out = []
    first = int(ra["first_strip"])
    for k in range(len(ra["strip_y"])):
        idx = first + k
        left = idx * STRIP_W + ra["drift"]
        x0, x1 = int(left + 24), int(left + STRIP_W - 24)
        if x0 < 0 or x1 + drift + 2 > ga.shape[1]:
            continue
        band_a = ga[top:bottom, x0:x1]
        bx0 = int(round(x0 + drift))
        best, best_dy = None, 0
        for dy in range(-90, 91):
            if top + dy < 0 or bottom + dy > gb.shape[0]:
                continue
            band_b = gb[top + dy:bottom + dy, bx0:bx0 + (x1 - x0)]
            e = float(np.mean((band_a - band_b) ** 2))
            if best is None or e < best:
                best, best_dy = e, dy
        out.append({"index": idx, "direction": "up" if idx % 2 == 0 else "down", "dy": best_dy, "error": round(best, 2),
                    "expected": round((rb["strip_y"][idx - int(rb["first_strip"])] - ra["strip_y"][k]), 1)})
    return drift, out


def sheet(folder):
    """A contact sheet of every capture tag in `folder` (game/tools/load_shots.gd), with the strips' measured motion."""
    import glob
    import json
    reports = []
    for js in sorted(glob.glob(os.path.join(folder, "*_shots.json"))):
        data = json.load(open(js, encoding="utf-8"))
        shots = data["shots"]
        tag = data["tag"]
        if not shots:
            continue
        thumbs = []
        for row in shots:
            im = Image.open(os.path.join(folder, row["file"])).convert("RGB")
            th = im.resize((360, round(im.height * 360 / im.width)), Image.LANCZOS)
            thumbs.append((row, th))
        h = max(t.height for _, t in thumbs)
        f = ImageFont.truetype(os.path.join(FONTS, "Bitter.ttf"), 24)
        fb = ImageFont.truetype(os.path.join(FONTS, "AlfaSlabOne-Regular.ttf"), 30)
        cols = 5
        rows = (len(thumbs) + cols - 1) // cols
        sh = Image.new("RGB", (cols * 380 + 20, 70 + rows * (h + 60)), (36, 27, 20))
        d = ImageDraw.Draw(sh)
        d.text((20, 16), "Loading screen %s%s%s" % (tag, (" tilt %g" % data["tilt"]) if data.get("tilt") else "",
                                                     ("  entrance: %s" % data["entrance"]) if data.get("entrance") else ""),
               font=fb, fill=(243, 230, 200))
        for i, (row, th) in enumerate(thumbs):
            x = 20 + (i % cols) * 380
            y = 70 + (i // cols) * (h + 60)
            sh.paste(th, (x, y))
            label = "%.3f s" % row["clock"] + ("  dissolve %.0f%%" % (row["dissolve"] * 100) if row["dissolve"] >= 0 else "")
            d.text((x, y + th.height + 8), label, font=f, fill=(243, 230, 200))
        out = os.path.join(folder, "%s_contact.png" % tag)
        sh.save(out)
        # the motion between the frame at 0.5 s and the one at 1.2 s, above the plate (pass 119: the slam's marks; the
        # first still frame from 0.8 s on, after the shake, and the last before the dissolve)
        by = {r["file"].rsplit("_", 1)[-1].split(".")[0]: r for r in shots}
        rep = {"tag": tag, "sheet": out}
        still = [r for r in shots if r["dissolve"] < 0 and r["clock"] >= 0.8 - 1e-3]
        if "t0500" in by and "t1200" in by:
            ra, rb = by["t0500"], by["t1200"]
        elif len(still) >= 2:
            ra, rb = still[0], still[-1]
        else:
            ra = rb = None
        if ra is not None:
            a = Image.open(os.path.join(folder, ra["file"]))
            b = Image.open(os.path.join(folder, rb["file"]))
            # below the plate's rest (in the 0.5 s frame the plate is still falling through the top half)
            top = int(rb["plate_foot"][1] + 70)
            drift, strips_ = measure_motion(a, b, ra, rb, top, int(rb["size"][1] - 100))
            rep.update({"dt": round(rb["clock"] - ra["clock"], 3), "drift_px": round(drift, 2), "strips": strips_})
        reports.append(rep)
        print("sheet: %s" % out)
        for st in rep.get("strips", []):
            print("  strip %3d %-4s measured %+4d px, handed to the shader %+6.1f px" % (
                st["index"], st["direction"], st["dy"], st["expected"]))
    json.dump(reports, open(os.path.join(folder, "motion.json"), "w", encoding="utf-8"), indent=2)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--review-only", action="store_true")
    ap.add_argument("--mock")
    ap.add_argument("--h", type=int, default=1920)
    ap.add_argument("--sheet", help="a folder of game/tools/load_shots.gd captures: their contact sheets and motion")
    args = ap.parse_args()
    if args.sheet:
        sheet(args.sheet)
        raise SystemExit(0)
    sl = silhouettes()
    ac = accents()
    review(sl, ac)
    if not args.review_only:
        w = strips(sl, ac)
        pimg = plate()
        write_boot_constants(w, pimg)
        if args.mock:
            mock(args.mock, args.h, w, pimg)
