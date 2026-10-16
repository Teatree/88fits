"""Pass 83 (lane SCENE): the ground shadow of every painted prop and structure, measured from its painting.

For each entry of game/art/sprites/props/props.json (a PNG whose quad is `height` metres square, the figure standing on
its bottom edge) the opaque pixels give the foot (the bottom 8% of the figure) and the body (its lower 45%); the shadow
is an ellipse as wide as a blend of the two, 0.6 of that deep (the creatures' blobs' proportion), centred under the
painted foot (which stands a little up its quad: z puts the shadow where that foot meets the ground as the camera sees it). Written as the entry's `shadow`
{w, d, x, z, a} in shares of the quad's height (PropField multiplies them by the drawn height; StructureManager by its
painting's), so a re-painted prop is measured again in one run. Hand-tuned entries are kept unless --force.

  python tools/prop_shadows.py [--only id,id] [--force] [--sheet out.png]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIR = os.path.join(REPO, "game", "art", "sprites", "props")

# paintings with their own sand patch painted at the foot (the bones, the skulls): a lighter shadow, no wider than it
PATCHED = {"skull": 0.3, "skull_small": 0.28, "bones": 0.28, "signpost": 0.4}
# the strength of the rest by build: the solid things darker than the airy ones
SOLID = {"boulder", "boulder_b", "rock_big", "rock_small", "barrel_cactus", "barrel_cactus_b"}
AIRY = {"dead_shrub", "dead_shrub_b", "dead_tree", "creosote_bush", "ocotillo", "ocotillo_b", "palo_verde", "brittlebush"}


def measure(png):
    im = Image.open(png).convert("RGBA")
    a = np.asarray(im)[:, :, 3] > 128
    h, w = a.shape
    rows = np.nonzero(a.any(1))[0]
    if len(rows) == 0:
        return None
    yt, yb = rows.min(), rows.max()
    fh = yb - yt + 1

    def extent(y0):
        band = a[max(y0, 0): yb + 1]
        cols = np.nonzero(band.any(0))[0]
        return (cols.min(), cols.max() + 1) if len(cols) else (w // 2, w // 2)

    fl, fr = extent(int(yb - 0.08 * fh))
    bl, br = extent(int(yb - 0.45 * fh))
    foot_w = (fr - fl) / w
    body_w = (br - bl) / w
    sw = max(0.16, (0.45 * foot_w + 0.55 * body_w) * 1.45)
    return {
        "w": round(sw, 3),
        "d": round(sw * 0.7, 3),
        "x": round(((fl + fr) * 0.5 - w * 0.5) / w, 3),
        # the painted foot stands this far up its quad, which leans back to face the camera: on the ground it reads
        # that far up over sin(pitch) behind the quad's foot (the run's camera and the title's, 46 degrees)
        "z": round(-((h - 1 - yb) / h) / math.sin(math.radians(46.0)), 3),
        "foot_from_bottom": round((h - 1 - yb) / h, 3),
    }


def strength(id_):
    if id_ in PATCHED:
        return PATCHED[id_]
    if id_ in SOLID or id_.startswith("st_"):
        return 0.55
    if id_ in AIRY:
        return 0.4
    return 0.48


def main():
    args = sys.argv[1:]
    only = None
    force = "--force" in args
    sheet = None
    if "--only" in args:
        only = args[args.index("--only") + 1].split(",")
    if "--sheet" in args:
        sheet = args[args.index("--sheet") + 1]
    mp = os.path.join(DIR, "props.json")
    man = json.load(open(mp, encoding="utf-8"))
    for id_, row in man.items():
        if only and id_ not in only:
            continue
        if "shadow" in row and not force:
            continue
        m = measure(os.path.join(DIR, row.get("file", id_ + ".png")))
        if m is None:
            continue
        sh = {"w": m["w"], "d": m["d"], "x": m["x"], "z": m["z"], "a": strength(id_)}
        if id_ in PATCHED:
            sh["w"] = round(sh["w"] * 0.8, 3)
            sh["d"] = round(sh["d"] * 0.8, 3)
        row["shadow"] = sh
        print("%-18s w %.3f d %.3f x %+.3f a %.2f  (foot %.3f up)" % (id_, sh["w"], sh["d"], sh["x"], sh["a"], m["foot_from_bottom"]))
    json.dump(man, open(mp, "w", encoding="utf-8", newline="\n"), indent=1)
    if sheet:
        draw_sheet(man, sheet)


def draw_sheet(man, out):
    """Every painting standing on sand over its shadow as a flat ellipse (a quick look; the game's own is the test)."""
    cell = 220
    ids = list(man.keys())
    cols = 7
    rows = (len(ids) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell, rows * cell), (226, 190, 140, 255))
    dr = ImageDraw.Draw(img)
    for i, id_ in enumerate(ids):
        row = man[id_]
        p = os.path.join(DIR, row.get("file", id_ + ".png"))
        if not os.path.exists(p) or "shadow" not in row:
            continue
        x0, y0 = (i % cols) * cell, (i // cols) * cell
        s = row["shadow"]
        size = int(cell * 0.85)
        foot = (x0 + cell // 2 + s["x"] * size, y0 + cell - 18)
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        rw, rd = s["w"] * size * 0.5, s["d"] * size * 0.5 * 0.72
        sd.ellipse([foot[0] - rw, foot[1] - rd, foot[0] + rw, foot[1] + rd], fill=(13, 8, 20, int(255 * s["a"])))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(rw * 0.25)))
        p_im = Image.open(p).convert("RGBA").resize((size, size), Image.LANCZOS)
        img.alpha_composite(p_im, (x0 + (cell - size) // 2, y0 + cell - 18 - size))
        dr.text((x0 + 4, y0 + 4), id_, fill=(40, 20, 10, 255))
    img.save(out)


if __name__ == "__main__":
    main()
