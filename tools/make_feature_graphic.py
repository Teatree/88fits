"""Feature graphics (1024x500): an AI background + the game's own hero cut-outs + the wordmark in the game's slab font."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

REPO = "D:/_projects/88fits"
OUT = REPO + "/tools/dl/feature_graphic"
HERO = REPO + "/game/art/ui/wanted/hero_%s.png"
SLAB = REPO + "/game/ui/fonts/AlfaSlabOne-Regular.ttf"
S = 2                      # compose at 2048x1000, save at 1024x500
FW, FH = 1024 * S, 500 * S


def cover(path):
    im = Image.open(path).convert("RGB")
    sc = max(FW / im.width, FH / im.height)
    im = im.resize((round(im.width * sc), round(im.height * sc)), Image.LANCZOS)
    x, y = (im.width - FW) // 2, (im.height - FH) // 2
    return im.crop((x, y, x + FW, y + FH)).convert("RGBA")


def hero(name, height, flip=False):
    im = Image.open(HERO % name).convert("RGBA")
    im = im.crop(im.getbbox())
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    sc = height / im.height
    return im.resize((round(im.width * sc), round(height)), Image.LANCZOS)


def place(canvas, im, cx, foot_y, glow=True):
    """Stand a cut-out with its feet at foot_y: a ground shadow and a warm rim of light behind it."""
    x, y = int(cx - im.width / 2), int(foot_y - im.height)
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    w = im.width * 0.62
    d.ellipse((cx - w / 2, foot_y - 14 * S, cx + w / 2, foot_y + 10 * S), fill=(40, 14, 8, 150))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(7 * S)))
    if glow:
        a = im.split()[3]
        rim = Image.new("RGBA", im.size, (255, 214, 140, 0))
        rim.putalpha(a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(5 * S)).point(lambda v: v * 0.55))
        canvas.alpha_composite(rim, (x, y))
    canvas.alpha_composite(im, (x, y))


def wordmark(canvas, cx, top, size1, size2):
    """OUTLAW / SURVIVORS: cream-to-gold slab letters, a thick dark-brown edge and a drop shadow."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    lines = [("OUTLAW", size1), ("SURVIVORS", size2)]
    y = top
    boxes = []
    for text, size in lines:
        f = ImageFont.truetype(SLAB, size)
        l, t, r, b = f.getbbox(text)
        boxes.append((text, f, cx - (r - l) / 2 - l, y - t, b - t))
        y += (b - t) + size * 0.16
    # shadow
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    for text, f, x, yy, _ in boxes:
        d.text((x + 6 * S, yy + 8 * S), text, font=f, fill=(25, 8, 4, 190), stroke_width=9 * S, stroke_fill=(25, 8, 4, 190))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(5 * S)))
    # edge
    d = ImageDraw.Draw(layer)
    for text, f, x, yy, _ in boxes:
        d.text((x, yy), text, font=f, fill=(58, 24, 12, 255), stroke_width=8 * S, stroke_fill=(58, 24, 12, 255))
    canvas.alpha_composite(layer)
    # fill: a vertical cream -> gold gradient through the letters' mask
    mask = Image.new("L", canvas.size, 0)
    dm = ImageDraw.Draw(mask)
    for text, f, x, yy, _ in boxes:
        dm.text((x, yy), text, font=f, fill=255)
    bb = mask.getbbox()
    grad = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for yy in range(bb[1], bb[3] + 1):
        k = (yy - bb[1]) / max(1, bb[3] - bb[1])
        c = tuple(round(a + (b - a) * k) for a, b in zip((255, 246, 222), (240, 168, 52)))
        gd.line((0, yy, FW, yy), fill=c + (255,))
    canvas.paste(grad, (0, 0), mask)


def vignette(canvas, strength=110):
    v = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(v)
    d.ellipse((-FW * 0.25, -FH * 0.45, FW * 1.25, FH * 1.45), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(120 * S))
    dark = Image.new("RGBA", canvas.size, (30, 10, 8, strength))
    dark.putalpha(Image.eval(v, lambda p: int((255 - p) * strength / 255)))
    canvas.alpha_composite(dark)


def posse(bg):
    """The posse in front of the sun on the left, the swarm on the right under the wordmark."""
    c = cover(bg)
    vignette(c)
    foot = FH - 26 * S
    for name, x, flip in (("solenne", 95, False), ("calavera", 165, False), ("astro", 385, True), ("may_g", 455, True)):
        place(c, hero(name, 290 * S, flip), x * S, foot - 34 * S)
    place(c, hero("fadeaway_c", 340 * S, True), 345 * S, foot - 10 * S)
    place(c, hero("drifter", 400 * S), 250 * S, foot + 6 * S)
    wordmark(c, 770 * S, 34 * S, 92 * S, 69 * S)
    return c


def swarm(bg):
    c = cover(bg)
    vignette(c, 90)
    wordmark(c, 560 * S, 30 * S, 84 * S, 63 * S)
    place(c, hero("drifter", 470 * S), 220 * S, FH - 18 * S)
    return c


if __name__ == "__main__":
    which = sys.argv[1:] or ["klein", "dev"]
    for m in which:
        for kind, fn in (("posse", posse), ("swarm", swarm)):
            bg = os.path.join(OUT, "bg_%s_%s.png" % (m, kind))
            if not os.path.exists(bg):
                continue
            im = fn(bg).convert("RGB").resize((1024, 500), Image.LANCZOS)
            out = os.path.join(OUT, "feature_%s_%s.png" % (m, kind))
            im.save(out)
            print(out)
