"""Google Play screenshots (pass 110): a raw 1080x1920 capture with a caption band across the bottom, the way the genre's
listings do it (Lonely Survivor: one idea in two or three words on a shaped band; Pickle Pete: a big word over a small one,
a band colour per shot). The band is the Wanted kit's: a torn paper edge outlined in ink, the shot's colour, the caption in
Alfa Slab One in paper with a hard ink shadow, the small line in Lilita One. The hero is framed by the capture (the arena's
Screenshot framing puts him at the centre of the area above the band: 1920 - BAND_H).

    python tools/make_store_shots.py --src <raw.png> --out <shot.png> --big "MASSIVE" [--small "Hordes!"] [--colour rock]
    python tools/make_store_shots.py --plan docs/store/plan.json       (every shot of a plan: [{src, out, big, small, colour}])
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(REPO, "game", "ui", "fonts")
W, H = 1080, 1920
BAND_H = 330              # the caption band's height under its torn edge
EDGE = 26                 # how far the torn edge wanders
PAPER = (243, 230, 200)
INK = (36, 27, 20)
COLOURS = {               # ui/wanted/W.gd tokens
    "rock": (180, 71, 43), "plum": (74, 51, 88), "rare": (62, 110, 158), "epic": (138, 79, 176), "sage": (110, 139, 94),
    "ember": (217, 102, 42), "brass": (201, 147, 47), "ink": INK, "turquoise": (63, 143, 138), "bad": (125, 31, 22),
}


def torn_edge(seed):
    """The band's top edge: a ragged line across the width (paper torn by hand: small teeth on a slow wave)."""
    rnd = random.Random(seed)
    pts = []
    x = 0
    phase = rnd.random() * 6.28
    while x <= W:
        y = H - BAND_H + math.sin(x / 170.0 + phase) * EDGE * 0.45 + rnd.uniform(-EDGE * 0.35, EDGE * 0.35)
        pts.append((x, y))
        x += rnd.randint(14, 30)
    pts.append((W, pts[-1][1]))
    return pts


def fit_font(path, text, max_w, size):
    while size > 20:
        f = ImageFont.truetype(path, size)
        if f.getbbox(text)[2] <= max_w:
            return f
        size -= 4
    return ImageFont.truetype(path, size)


def shadowed(draw, xy, text, font, fill, shadow=INK, off=(0, 9), stroke=7):
    x, y = xy
    draw.text((x + off[0], y + off[1]), text, font=font, fill=shadow, stroke_width=stroke, stroke_fill=shadow)
    draw.text((x, y), text, font=font, fill=fill, stroke_width=stroke, stroke_fill=INK)


def compose(src, out, big, small="", colour="rock", seed=7, fit=1.0, top=0):
    shot = Image.open(src).convert("RGB")
    if shot.size != (W, H):
        s = max(W / shot.width, H / shot.height)
        shot = shot.resize((round(shot.width * s), round(shot.height * s)), Image.LANCZOS)
        shot = shot.crop(((shot.width - W) // 2, (shot.height - H) // 2, (shot.width - W) // 2 + W, (shot.height - H) // 2 + H))
    if fit < 1.0:
        # a screen whose content runs to the bottom (the level-up cards) is shrunk to fit above the band, `top` px
        # down, over a blurred, darkened copy of itself filling the frame
        back = shot.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * 0.7))
        small_shot = shot.resize((round(W * fit), round(H * fit)), Image.LANCZOS)
        back.paste(small_shot, ((W - small_shot.width) // 2, top))
        shot = back
    edge = torn_edge(seed)
    band = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(band)
    poly = edge + [(W, H), (0, H)]
    # a soft dark fall-off above the edge so the band sits on the scene, then the ink rim, then the colour
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shade).polygon([(x, y - 30) for x, y in edge] + [(W, H), (0, H)], fill=(0, 0, 0, 120))
    shade = shade.filter(ImageFilter.GaussianBlur(18))
    d.polygon([(x, y - 9) for x, y in edge] + [(W, H), (0, H)], fill=INK + (255,))
    d.polygon(poly, fill=COLOURS.get(colour, COLOURS["rock"]) + (255,))
    # a faint paper grain on the band
    rnd = random.Random(seed + 1)
    for _ in range(2600):
        x, y = rnd.randint(0, W - 1), rnd.randint(H - BAND_H - EDGE, H - 1)
        a = rnd.randint(8, 22)
        d.point((x, y), fill=(255, 255, 255, a) if rnd.random() < 0.5 else (0, 0, 0, a))
    img = shot.convert("RGBA")
    img.alpha_composite(shade)
    img.alpha_composite(band)
    draw = ImageDraw.Draw(img)
    top = H - BAND_H + EDGE + 6
    room = BAND_H - EDGE - 30
    fb = fit_font(os.path.join(FONTS, "AlfaSlabOne-Regular.ttf"), big, W - 120, 150 if small else 168)
    bb = fb.getbbox(big)
    if small:
        fs = fit_font(os.path.join(FONTS, "LilitaOne.ttf"), small, W - 200, 92)
        sb = fs.getbbox(small)
        total = (bb[3] - bb[1]) + 14 + (sb[3] - sb[1])
        y0 = top + (room - total) / 2 - bb[1]
        shadowed(draw, ((W - (bb[2] - bb[0])) / 2 - bb[0], y0), big, fb, PAPER)
        y1 = y0 + bb[3] + 14 - sb[1]
        shadowed(draw, ((W - (sb[2] - sb[0])) / 2 - sb[0], y1), small, fs, (246, 215, 94), off=(0, 6), stroke=5)
    else:
        y0 = top + (room - (bb[3] - bb[1])) / 2 - bb[1]
        shadowed(draw, ((W - (bb[2] - bb[0])) / 2 - bb[0], y0), big, fb, PAPER)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.convert("RGB").save(out)
    print("make_store_shots:", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--out")
    ap.add_argument("--big", default="")
    ap.add_argument("--small", default="")
    ap.add_argument("--colour", default="rock")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--fit", type=float, default=1.0)
    ap.add_argument("--top", type=int, default=0)
    ap.add_argument("--plan")
    a = ap.parse_args()
    if a.plan:
        for s in json.load(open(a.plan, encoding="utf-8")):
            compose(os.path.join(REPO, s["src"]), os.path.join(REPO, s["out"]), s["big"], s.get("small", ""),
                    s.get("colour", "rock"), int(s.get("seed", 7)), float(s.get("fit", 1.0)), int(s.get("top", 0)))
        return
    compose(a.src, a.out, a.big, a.small, a.colour, a.seed, a.fit, a.top)


if __name__ == "__main__":
    main()
