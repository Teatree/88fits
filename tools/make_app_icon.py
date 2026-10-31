"""The launcher icon from Garry's picture (pass 116, lane RESULTS; Garry: "change the icon to the one I shared ... It's
called Desert Gunslinger Battles Scorpion Swarm.png. Process exactly that, don't regenerate it."). Crops and scales only:

  game/icon.png        1024: the gunslinger's face and his revolver (CROP, in the 1254 px picture)
  game/icon_192.png    192: a tighter crop (SMALL) so the face and the gun read at launcher size
  game/icon_fg_432.png Android's adaptive foreground: the picture round the same centre, wide enough that the launcher's
                       safe middle 66% shows CROP; past the picture's edge its edge pixels carry on (blurred)
  game/icon_bg_432.png the adaptive background: the picture blurred to a wash of its own colours

Then python tools/make_win_icon.py (its SUBJECT box is CROP's face and gun) and python tools/make_splash.py.
The pass 115 icons are kept in tools/dl/backup/app_icon_v098/.

  python tools/make_app_icon.py [--src <picture>] [--review out.png]
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "_REFERENCES", "2d", "Desert Gunslinger Battles Scorpion Swarm.png")
GAME = os.path.join(ROOT, "game")
# square crops in the source's pixels (x0, y0, side)
CROP = (100, 30, 900)
SMALL = (170, 60, 780)
SAFE = 0.66


def crop(src, box, size):
    x, y, s = box
    return src.crop((x, y, x + s, y + s)).resize((size, size), Image.LANCZOS)


def padded(src, cx, cy, side):
    """A square of `side` round (cx, cy), the picture's edge pixels carried on (and blurred) past its border."""
    a = np.asarray(src)
    pad = int(side)
    big = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
    im = Image.fromarray(big)
    blur = im.filter(ImageFilter.GaussianBlur(24))
    blur.paste(src, (pad, pad))
    x0, y0 = int(round(cx - side / 2)) + pad, int(round(cy - side / 2)) + pad
    return blur.crop((x0, y0, x0 + int(side), y0 + int(side)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--review", default="")
    a = ap.parse_args()
    src = Image.open(a.src).convert("RGB")
    crop(src, CROP, 1024).save(os.path.join(GAME, "icon.png"))
    crop(src, SMALL, 192).save(os.path.join(GAME, "icon_192.png"))
    x, y, s = CROP
    fg = padded(src, x + s / 2, y + s / 2, s / SAFE).resize((432, 432), Image.LANCZOS)
    fg.save(os.path.join(GAME, "icon_fg_432.png"))
    src.resize((432, 432), Image.LANCZOS).filter(ImageFilter.GaussianBlur(30)).save(os.path.join(GAME, "icon_bg_432.png"))
    if a.review:
        sizes = [48, 96, 192, 512]
        sheet = Image.new("RGB", (sum(sizes) + 40 * 5 + 432 + 40, 512 + 80), (40, 34, 30))
        xx = 40
        for sz in sizes:
            box = SMALL if sz <= 192 else CROP
            sheet.paste(crop(src, box, sz), (xx, 40))
            xx += sz + 40
        # the adaptive icon as a round launcher shows it: the foreground's middle under a circle
        m = Image.new("L", (432, 432), 0)
        from PIL import ImageDraw
        r = 432 * SAFE / 2
        ImageDraw.Draw(m).ellipse((216 - r, 216 - r, 216 + r, 216 + r), fill=255)
        dark = Image.new("RGB", (432, 432), (40, 34, 30))
        sheet.paste(Image.composite(fg, dark, m), (xx, 40))
        sheet.save(a.review)
    print("app icons written from", os.path.basename(a.src))


if __name__ == "__main__":
    main()
