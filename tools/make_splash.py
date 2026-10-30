"""The boot splash (pass 54, Garry: Godot's logo gone at start-up): `game/art/ui/splash.png`, 1080 x 1920, the Wanted
paper, the launcher painting (`game/icon.png`) as a disc 560 px across in a 6 px ink ring with a hard ink shadow,
the game's name under it in Alfa Slab at 140 px in ink with the title screen's hard brass shadow (8 px), and a line in
Bitter. The colours are read from game/ui/wanted/W.gd, so the splash follows the UI's palette.

Pass 115 (Garry: "Rename the game to Outlaw Survivors, but only in the game itself ... we just write 'Outlaw' with big
fat text and the 'Drag Dodge Survive' is replaced with simply 'Survivors'"): the name is OUTLAW (it was "88fits") and
the line under it SURVIVORS (it was "A survivor shooter" in Bitter italic 36 px), set the way the title sets its line:
Bitter 600 capitals at TAG_PX with TAG_TRACK em after every letter, in ink. The words are W.gd's GAME_WORD and
GAME_LINE, read like the colours.

Pass 58 (Garry: "for like a second or 2 right before the Main Menu loads I see a kind of a broken version of our Loading
screen - with brown lines at the top and bottom visible ... My phone is a Pixel 8 pro, might be resolution thing"): the
picture had an ink band at its top and its foot, and Godot's boot splash (stretch mode Keep) fits a portrait picture to
the screen's width and centres it, so on a 20:9 phone the paper ran on above and below it and the two bands floated
inside the screen. The picture is now paper to every edge, exactly the boot splash's bg_color, so it melts into the
screen whatever its shape. The disc, the title, the line, and under them the loading bar's empty look (its hard shadow,
its ink border, its aged track) and its word LOADING sit in the middle of the paper: the picture is the loading screen
at 0 %. The loading screen (game/ui/Boot.gd) draws this same picture at the same place and paints the brass fill into
the track in the same draw, so the whole screen is one layer and its fade into the title is even (fix round: with the
bar and its word drawn over the picture and the paper under it, the fade had shown two lines across a 20:9 screen at
the picture's top and foot, and the bar outlasted the rest). The bar's rect in the picture's pixels is written into
Boot.gd (`const BAR`, `const LABEL_Y`, ...), so the two never drift apart.

Also `game/art/ui/splash_icon.png`, 768 x 768 on transparent: the same disc, ring and shadow for Android's own splash
screen (export preset `splash_screen/icon`), which shows the icon 288 dp across masked to the middle two thirds, so the
disc sits inside that circle (a 192 px launcher icon would be stretched six times over on a phone).

project.godot `application/boot_splash/*` points at the splash (paper behind it); the Android preset turns Godot's own
boot splash off and paints its system splash in the same paper with splash_icon.png.

  python tools/make_splash.py [--preview p.png]     (--preview: the picture with the bar 60 % full, to look at)
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "game")
OUT = os.path.join(GAME, "art", "ui", "splash.png")
OUT_ICON = os.path.join(GAME, "art", "ui", "splash_icon.png")
BOOT = os.path.join(GAME, "ui", "Boot.gd")
FONTS = os.path.join(GAME, "ui", "fonts")
SIZE = (1080, 1920)
ICON = 560            # the painting's disc
RING = 6
SHADOW = 10           # the disc's hard shadow, down and right
TITLE_PX = 140
TITLE_SHADOW = 8
TAG_PX = 30           # the line under the name, as the title screen sets it (W.label, Bitter 600 capitals)
TAG_TRACK = 0.3       # letter-spacing in em after every letter (the title's tagline: W.label(..., 30, W.INK, 0.3))
GAP_TITLE = 70        # from the disc's ring to the title's ink
GAP_TAG = 30
# the loading bar under the line, drawn empty in the picture (Boot.gd paints its fill): the bar's outer box with its
# ink border (WBar), its hard shadow, and the word under it in Bitter 600 capitals (W.label: line box 1.2 em)
GAP_BAR = 84          # from the line's ink to the bar
BAR_W = 520
BAR_H = 34
BAR_BORDER = 4
BAR_SHADOW = 5
GAP_LABEL = 16        # from the bar's shadow to the word's line box
LABEL_PX = 28
LABEL_TRACK = 0.3     # letter-spacing in em, after every letter (W.label's FontVariation spacing_glyph)
LABEL_WORD = "LOADING"
LABEL_BOX = round(1.2 * LABEL_PX)
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


def w_string(name):
    """A string constant of the Wanted UI kit (`const NAME := "..."` in W.gd): the game's name words (pass 115)."""
    src = open(os.path.join(GAME, "ui", "wanted", "W.gd"), encoding="utf-8").read()
    m = re.search(r'^const %s := "([^"]*)"' % name, src, re.M)
    if not m:
        raise SystemExit("W.gd has no %s" % name)
    return m.group(1)


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


def fonts():
    slab = ImageFont.truetype(os.path.join(FONTS, "AlfaSlabOne-Regular.ttf"), TITLE_PX)
    line = ImageFont.truetype(os.path.join(FONTS, "Bitter.ttf"), TAG_PX)
    line.set_variation_by_axes([600])
    return slab, line


def tracked_box(text, font, track_px):
    """The ink box (left, top, width, height) of `text` set letter by letter with `track_px` after every letter but the
    last, as W.label's FontVariation spacing does: left and top against the pen at (0, baseline 0)."""
    d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    x = 0.0
    l = t = 10 ** 6
    r = b = -10 ** 6
    for ch in text:
        bl, bt, br, bb = d.textbbox((x, 0), ch, font=font, anchor="ls")
        if br > bl:
            l, t, r, b = min(l, bl), min(t, bt), max(r, br), max(b, bb)
        x += font.getlength(ch) + track_px
    return l, t, r - l, b - t


def tracked_text(d, text, font, track_px, x_left, baseline, color):
    """`text` drawn letter by letter from the pen at (x_left, baseline), `track_px` after every letter."""
    x = x_left
    for ch in text:
        d.text((x, baseline), ch, font=font, fill=color, anchor="ls")
        x += font.getlength(ch) + track_px


def layout():
    """Where everything goes, in the picture's pixels: the disc's centre, the title's and the line's ink boxes, and
    under them the loading bar (x, y, w, h of its outer box; Boot.gd fills its track) and its word (the top of its line
    box). The whole group, from the ring's top to the word's foot, sits in the middle of the paper."""
    slab, line = fonts()
    d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    title, tag = w_string("GAME_WORD").upper(), w_string("GAME_LINE").upper()
    tl, tt, tw, th = text_box(d, title, slab)
    gl, gt, gw, gh = tracked_box(tag, line, round(TAG_PX * TAG_TRACK))
    group = (ICON + RING * 2 + GAP_TITLE + th + GAP_TAG + gh + GAP_BAR + BAR_H + BAR_SHADOW + GAP_LABEL + LABEL_BOX)
    top = round((SIZE[1] - group) * 0.5)
    cx = SIZE[0] * 0.5
    cy = top + RING + ICON * 0.5
    ty = cy + ICON * 0.5 + RING + GAP_TITLE
    gy = ty + th + GAP_TAG
    bar_y = round(gy + gh + GAP_BAR)
    bar = (round(cx - BAR_W * 0.5), bar_y, BAR_W, BAR_H)
    label_y = bar_y + BAR_H + BAR_SHADOW + GAP_LABEL
    return {
        "slab": slab, "line": line, "title": title, "tag": tag, "centre": (cx, cy),
        "title_box": (tl, tt, tw, th), "tag_box": (gl, gt, gw, gh), "title_y": ty, "tag_y": gy,
        "bar": bar, "label_y": label_y, "group": (top, top + group),
    }


def empty_bar(d, bar, ink, aged):
    """The bar as the kit's WBar draws it with nothing filled: a hard ink shadow BAR_SHADOW px down and right, the ink
    box, and the aged track inside a BAR_BORDER px border (PIL's rectangles include their last pixel)."""
    x, y, w, h = bar
    s, b = BAR_SHADOW, BAR_BORDER
    d.rectangle((x + s, y + s, x + w - 1 + s, y + h - 1 + s), fill=ink)
    d.rectangle((x, y, x + w - 1, y + h - 1), fill=ink)
    d.rectangle((x + b, y + b, x + w - 1 - b, y + h - 1 - b), fill=aged)


def bar_word(d, top, color):
    """The bar's word as W.label sets it: Bitter 600 capitals at LABEL_PX with LABEL_TRACK em after every letter, the
    letters centred, the baseline where the kit's line box puts it (Bitter's ascent, 0.935 em, rounded)."""
    f = ImageFont.truetype(os.path.join(FONTS, "Bitter.ttf"), LABEL_PX)
    f.set_variation_by_axes([600])
    track = round(LABEL_PX * LABEL_TRACK)
    adv = [f.getlength(ch) for ch in LABEL_WORD]
    x = SIZE[0] * 0.5 - (sum(adv) + track * (len(LABEL_WORD) - 1)) * 0.5
    base = top + round(0.935 * LABEL_PX)
    for ch, a in zip(LABEL_WORD, adv):
        d.text((x, base), ch, font=f, fill=color, anchor="ls")
        x += a + track


def splash():
    paper = w_color("PAPER")
    ink = w_color("INK")
    soft = w_color("INK_SOFT")
    brass = w_color("BRASS")
    aged = w_color("AGED")
    L = layout()
    img = Image.new("RGBA", SIZE, paper + (255,))
    cx, cy = L["centre"]
    badge(img, (cx, cy), ICON, RING, SHADOW, ink, Image.open(os.path.join(GAME, "icon.png")).convert("RGBA"))
    d = ImageDraw.Draw(img)
    tl, tt, tw, th = L["title_box"]
    ty = L["title_y"]
    tx = cx - tw * 0.5
    d.text((tx - tl + TITLE_SHADOW, ty - tt + TITLE_SHADOW), L["title"], font=L["slab"], fill=brass)
    d.text((tx - tl, ty - tt), L["title"], font=L["slab"], fill=ink)
    gl, gt, gw, gh = L["tag_box"]
    # the line in ink, as the title sets it; its ink box centred and its top at tag_y
    tracked_text(d, L["tag"], L["line"], round(TAG_PX * TAG_TRACK), cx - gw * 0.5 - gl, L["tag_y"] - gt, ink)
    empty_bar(d, L["bar"], ink, aged)
    bar_word(d, L["label_y"], soft)
    rgb = img.convert("RGB")
    _check_edges(rgb, paper)
    rgb.save(OUT, optimize=True)
    if os.path.getsize(OUT) > MAX_BYTES:
        # fewer colours, but the paper must stay the paper exactly (it is what the edges melt into)
        q = rgb.quantize(256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG).convert("RGB")
        _check_edges(q, paper)
        q.save(OUT, optimize=True)
    print("splash: %s %dx%d %d KB, group %d..%d, bar %s, word at %d" % (
        OUT, SIZE[0], SIZE[1], os.path.getsize(OUT) // 1024, L["group"][0], L["group"][1], L["bar"], L["label_y"]))
    return L


def _check_edges(rgb, paper):
    """Every pixel on the picture's four edges is the paper, so the boot splash's bg_color continues it seamlessly."""
    w, h = rgb.size
    edges = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    bad = [p for p in edges if rgb.getpixel(p) != paper]
    if bad:
        raise SystemExit("splash: %d edge pixels are not the paper (first %s = %s)" % (len(bad), bad[0], rgb.getpixel(bad[0])))


def write_boot_constants(L):
    """Boot.gd paints the bar's fill into the track this picture draws: the bar's outer box (`const BAR`, in the
    picture's pixels), its border, its hard shadow, the word's size and the top of its line box are written here, so a
    change of layout carries over."""
    src = open(BOOT, "rb").read().decode("utf-8")
    x, y, w, h = L["bar"]
    lines = {
        r"^const BAR := Rect2\([^)]*\)": "const BAR := Rect2(%d, %d, %d, %d)" % (x, y, w, h),
        r"^const LABEL_Y := [0-9.]+": "const LABEL_Y := %.1f" % L["label_y"],
        r"^const BAR_BORDER := [0-9]+": "const BAR_BORDER := %d" % BAR_BORDER,
        r"^const BAR_SHADOW := [0-9]+": "const BAR_SHADOW := %d" % BAR_SHADOW,
        r"^const LABEL_PX := [0-9]+": "const LABEL_PX := %d" % LABEL_PX,
    }
    new = src
    for pattern, line in lines.items():
        new, n = re.subn(pattern, line, new, flags=re.M)
        if n != 1:
            raise SystemExit("Boot.gd has no single `%s` line to write" % line.split(" := ")[0])
    if new != src:
        open(BOOT, "wb").write(new.encode("utf-8"))
        print("Boot.gd: BAR = %s, LABEL_Y = %.1f, BAR_BORDER = %d, BAR_SHADOW = %d, LABEL_PX = %d" % (
            L["bar"], L["label_y"], BAR_BORDER, BAR_SHADOW, LABEL_PX))


def preview(path, L, fill=0.6):
    """The picture with the bar `fill` full, the way Boot.gd paints the fill (to look at, not shipped)."""
    brass = w_color("BRASS")
    img = Image.open(OUT).convert("RGB")
    d = ImageDraw.Draw(img)
    x, y, w, h = L["bar"]
    b = BAR_BORDER
    d.rectangle((x + b, y + b, x + b + int((w - 2 * b) * fill) - 1, y + h - 1 - b), fill=brass)
    img.save(path)
    print("preview: %s" % path)


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
    lay = splash()
    write_boot_constants(lay)
    splash_icon()
    for i, a in enumerate(sys.argv):
        if a == "--preview" and i + 1 < len(sys.argv):
            preview(sys.argv[i + 1], lay)
