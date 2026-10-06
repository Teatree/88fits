"""The boot splash (pass 54, Garry: Godot's logo gone at start-up): `game/art/ui/splash.png`, 1080 x 1920, the Wanted
paper with an ink band at the top and the foot (as the UI's cutout band), the launcher painting (`game/icon.png`) as a
disc 560 px across in a 6 px ink ring with a hard ink shadow, "88fits" under it in Alfa Slab at 140 px in ink with the
title screen's hard brass shadow (8 px), and "A survivor shooter" in Bitter italic at 36 px in the soft ink. The colours
are read from game/ui/wanted/W.gd, so the splash follows the UI's palette.

Also `game/art/ui/splash_icon.png`, 768 x 768 on transparent: the same disc, ring and shadow for Android's own splash
screen (export preset `splash_screen/icon`), which shows the icon 288 dp across masked to the middle two thirds, so the
disc sits inside that circle (a 192 px launcher icon would be stretched six times over on a phone).

project.godot `application/boot_splash/*` points at the splash (paper behind it); the Android preset turns Godot's own
boot splash off and paints its system splash in the same paper with splash_icon.png.

  python tools/make_splash.py
"""
import os
import re

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "game")
OUT = os.path.join(GAME, "art", "ui", "splash.png")
OUT_ICON = os.path.join(GAME, "art", "ui", "splash_icon.png")
FONTS = os.path.join(GAME, "ui", "fonts")
SIZE = (1080, 1920)
BAND = 104            # the ink band at the top and at the foot
ICON = 560            # the painting's disc
RING = 6
SHADOW = 10           # the disc's hard shadow, down and right
TITLE_PX = 140
TITLE_SHADOW = 8
TAG_PX = 36
GAP_TITLE = 70        # from the disc's ring to the title's ink
GAP_TAG = 30
SUPER = 4             # discs are drawn this much bigger and scaled down, so their edges are smooth
ICON_CANVAS = 768
ICON_DISC = 464       # inside the system splash's mask (two thirds of the canvas, 512 px), ring and shadow included
MAX_BYTES = 600 * 1024


def w_color(name):
    """A colour constant of the Wanted UI kit (`const NAME := Color("rrggbb")` in W.gd) as an RGB tuple."""
    src = open(os.path.join(GAME, "ui", "wanted", "W.gd"), encoding="utf-8").read()
    m = re.search(r'^const %s := Color\("([0-9a-fA-F]{6})"\)' % name, src, re.M)
    if not m:
        raise SystemExit("W.gd has no %s" % name)
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def disc_mask(diameter, canvas, centre):
    """An anti-aliased disc as an L mask of `canvas` size."""
    big = Image.new("L", (canvas[0] * SUPER, canvas[1] * SUPER), 0)
    r = diameter * 0.5 * SUPER
    cx, cy = centre[0] * SUPER, centre[1] * SUPER
    ImageDraw.Draw(big).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return big.resize(canvas, Image.LANCZOS)


def badge(img, centre, diameter, ring, shadow, ink, painting):
    """The launcher painting as a disc in an ink ring with a hard ink shadow, drawn onto `img` (RGBA) at `centre`."""
    full = diameter + ring * 2
    solid = Image.new("RGBA", img.size, ink + (255,))
    img.paste(solid, (0, 0), disc_mask(full, img.size, (centre[0] + shadow, centre[1] + shadow)))
    img.paste(solid, (0, 0), disc_mask(full, img.size, centre))
    pic = painting.resize((diameter, diameter), Image.LANCZOS)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    left, top = int(round(centre[0] - diameter * 0.5)), int(round(centre[1] - diameter * 0.5))
    layer.paste(pic, (left, top))
    img.paste(layer, (0, 0), disc_mask(diameter, img.size, centre))


def text_box(draw, text, font):
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    return l, t, r - l, b - t


def splash():
    paper = w_color("PAPER")
    ink = w_color("INK")
    soft = w_color("INK_SOFT")
    brass = w_color("BRASS")
    img = Image.new("RGBA", SIZE, paper + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, SIZE[0], BAND - 1), fill=ink)
    d.rectangle((0, SIZE[1] - BAND, SIZE[0], SIZE[1]), fill=ink)
    slab = ImageFont.truetype(os.path.join(FONTS, "AlfaSlabOne-Regular.ttf"), TITLE_PX)
    italic = ImageFont.truetype(os.path.join(FONTS, "Bitter-Italic.ttf"), TAG_PX)
    italic.set_variation_by_axes([400])
    title, tag = "88fits", "A survivor shooter"
    tl, tt, tw, th = text_box(d, title, slab)
    gl, gt, gw, gh = text_box(d, tag, italic)
    # the disc, the title and the line below it, as one block in the middle of the paper between the bands
    block = ICON + RING * 2 + GAP_TITLE + th + GAP_TAG + gh
    top = BAND + (SIZE[1] - 2 * BAND - block) * 0.5
    cx = SIZE[0] * 0.5
    cy = top + RING + ICON * 0.5
    badge(img, (cx, cy), ICON, RING, SHADOW, ink, Image.open(os.path.join(GAME, "icon.png")).convert("RGBA"))
    d = ImageDraw.Draw(img)
    ty = cy + ICON * 0.5 + RING + GAP_TITLE
    tx = cx - tw * 0.5
    d.text((tx - tl + TITLE_SHADOW, ty - tt + TITLE_SHADOW), title, font=slab, fill=brass)
    d.text((tx - tl, ty - tt), title, font=slab, fill=ink)
    gy = ty + th + GAP_TAG
    d.text((cx - gw * 0.5 - gl, gy - gt), tag, font=italic, fill=soft)
    rgb = img.convert("RGB")
    rgb.save(OUT, optimize=True)
    if os.path.getsize(OUT) > MAX_BYTES:
        rgb.quantize(256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG).save(OUT, optimize=True)
    print("splash: %s %dx%d %d KB" % (OUT, SIZE[0], SIZE[1], os.path.getsize(OUT) // 1024))


def splash_icon():
    ink = w_color("INK")
    img = Image.new("RGBA", (ICON_CANVAS, ICON_CANVAS), (0, 0, 0, 0))
    ring = 5
    shadow = 8
    c = ICON_CANVAS * 0.5
    badge(img, (c, c), ICON_DISC, ring, shadow, ink, Image.open(os.path.join(GAME, "icon.png")).convert("RGBA"))
    img.save(OUT_ICON, optimize=True)
    print("splash icon: %s %dx%d %d KB" % (OUT_ICON, ICON_CANVAS, ICON_CANVAS, os.path.getsize(OUT_ICON) // 1024))


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    splash()
    splash_icon()
