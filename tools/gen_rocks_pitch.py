"""Pass 148 (lane ROCKS; Garry: the painted rocks "feel a little detached from the ground", the little rocks at their foot "at
a different angle from the 3D view"): the four rock paintings (rock_small, rock_big, boulder, boulder_b) painted again by
Klein over their Blender renders seen from the game's own camera pitch (tools/blender_rocks.py, ~48 degrees), the way
pass 127 painted the cart: the render is the last reference and the start of the painting. No pebbles at the foot and
no dark outline along the base: gen_art's outline is laid round the silhouette, then taken off every edge that faces
down in the painting's lower part (open_base), so the bottom reads as stone meeting sand.

  "$BLENDER" -b --python tools/blender_rocks.py
  python tools/gen_rocks_pitch.py [--only rock_big,...] [--seeds 4] [--force]      # candidates + review sheets
      [--renders <dir> --denoise 0.9 --tag p148b --clay]                                   (round 2: other renders, its own raw cache)
  python tools/gen_rocks_pitch.py --pick rock_big=2 boulder=0 ...                 # the picks -> game/art/sprites/props/<id>.png
                                                                                    (props.json untouched: same size, pivot, collider)
Candidates and sheets in tools/dl/p148/ROCKS/cands (--cands <dir>), raw paintings in tools/dl/ai_raw_props/<id>_p148_<seed>.png.
"""
import io
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402
import gen_props as gp  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "art", "sprites", "props")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
RENDERS = os.path.join(REPO, "tools", "dl", "p148", "ROCKS", "render")
CANDS = os.path.join(REPO, "tools", "dl", "p148", "ROCKS", "cands")

# id: (the original's raw painting, the style reference; subject; cell px; first seed)
ROCKS = {
    "rock_small": ("rock_small_18.png", "a small rounded sandstone rock, orange and tan with a few cracks", 128, 14801),
    "rock_big": ("rock_big_19.png", "a big rounded sandstone rock, orange and tan with cracks and a flat top", 256, 14811),
    "boulder": ("boulder_20.png", "a huge rounded sandstone boulder with layered orange and tan bands", 384, 14821),
    "boulder_b": ("boulder_b_8531.png", "a balanced rock: a big rounded sandstone boulder resting on top of a shorter, narrower "
                  "sandstone pedestal rock, layered tan and orange bands", 384, 14831),
}
DENOISE = 0.84
OUTLINE = (70, 46, 30, 230)

ARGS = sys.argv[1:]
FORCE = "--force" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
SEEDS = int(ARGS[ARGS.index("--seeds") + 1]) if "--seeds" in ARGS else 4
if "--cands" in ARGS:
    CANDS = os.path.abspath(ARGS[ARGS.index("--cands") + 1])
# round 2: the smoother renders (blender_rocks.py smooth=1 out=...), a stronger repaint, its own raw cache
if "--renders" in ARGS:
    RENDERS = os.path.abspath(ARGS[ARGS.index("--renders") + 1])
if "--denoise" in ARGS:
    DENOISE = float(ARGS[ARGS.index("--denoise") + 1])
TAG = ARGS[ARGS.index("--tag") + 1] if "--tag" in ARGS else "p148"
# --clay: the grey render (the shapes only) is shown, the colours left to the words and the style references
REF = "_ref_clay.png" if "--clay" in ARGS else "_ref.png"


def open_base(img, depth, lower=0.45):
    """The base's outline off: in the painting's lower part (below `lower` of its height), every pixel within `depth` px
    above a transparent one in its column is cleared, so the edges that face down (the ground line) lose the outline and
    the dark rim the painter drew there; the sides keep theirs."""
    a = np.asarray(img).copy()
    al = a[..., 3] > 40
    rows = np.nonzero(al.any(1))[0]
    if not len(rows):
        return img
    top, bot = rows.min(), rows.max()
    y0 = int(top + (bot - top) * lower)
    h = a.shape[0]
    clear = np.zeros(al.shape, bool)
    for d in range(1, depth + 1):
        below = np.zeros(al.shape, bool)
        below[:h - d] = ~al[d:]
        below[h - d:] = True
        clear |= al & below
    clear[:y0] = False
    out = a.copy()
    out[clear, 3] = 0
    # the lower part's edge smoothed (the column cut steps along a slanted base) and its faint fringe gone
    low = (out[..., 3] > 127).astype(np.uint8) * 255
    soft = np.asarray(Image.fromarray(low, "L").filter(ImageFilter.GaussianBlur(1.1))).astype(np.int32)
    alpha = out[..., 3].astype(np.int32)
    alpha[y0:] = np.minimum(alpha[y0:], soft[y0:])
    alpha[y0:][alpha[y0:] < 40] = 0
    out[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def finish(img, cell):
    cell_img, _ = ga.finish(img, cell, 0.9, True, None, 0.007, None, OUTLINE)
    # the outline's width plus the painter's own dark rim along the base
    depth = max(3, int(round(cell * 0.022)))
    return gp.mute(open_base(cell_img, depth))


def paint(id_, k):
    ref_raw, subject, cell, seed = ROCKS[id_]
    os.makedirs(RAW, exist_ok=True)
    s = seed + k * 977
    raw = os.path.join(RAW, "%s_%s_%d.png" % (id_, TAG, s))
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    bg = ga.BG_BLUE
    refs = list(ga.ensure_anchor_uploaded())
    refs.append(comfy.upload_pil(Image.open(os.path.join(RAW, ref_raw)).convert("RGB"), "p148_" + id_ + "_style.png"))
    shown = comfy.upload_pil(ga.on_screen(Image.open(os.path.join(RENDERS, id_ + REF)), True), "p148_" + id_ + "_render.png")
    prompt = ("Using exactly the same art style, line art, cel shading, palette and level of detail as the first reference images, repaint the "
              "rock of the last reference image as a painted desert prop for the same game: keep its silhouette, its proportions and its "
              "facets, seen from exactly the same high angle, looking down on it so its top is in view. " + subject + ". "
              + ("The last reference is a grey clay model: take only its shape and light from it and paint it in the warm orange, tan and "
                 "pinkish sandstone colours of the reference rocks, rounded lumps with crack lines between them. " if REF != "_ref.png" else "")
              + "Clean dark outline "
              "along its top and its sides only; its bottom edge, where it sits in the sand, has no outline and no dark rim: the stone's own "
              "colour simply ends there, a little dusty. One single rock, no pebbles, no small stones, no rubble around it, no ground patch, "
              "no cast shadow, nothing else in the frame. " + ga.STYLE + ". " + bg + ".")
    t0 = time.time()
    imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs + [shown], prefix="88fits/prop_" + id_ + "_p148", init=shown, denoise=DENOISE))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  rocks %-12s seed %-6d %5.0fs" % (id_, s, time.time() - t0))
    return img


def review(id_, cands):
    """The original and each candidate on sand, big and at about their size on the phone."""
    tiles = [("original", Image.open(os.path.join(REPO, "tools", "dl", "p148", "ROCKS", "before", id_ + ".png")).convert("RGBA"))]
    tiles += [("c%d" % k, c) for k, c in enumerate(cands)]
    big, small = 300, 110
    sheet = Image.new("RGBA", (len(tiles) * (big + 20) + 20, big + small + 70), (238, 205, 150, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(tiles):
        x = 20 + i * (big + 20)
        sheet.alpha_composite(im.resize((big, big), Image.LANCZOS), (x, 10))
        sheet.alpha_composite(im.resize((small, small), Image.LANCZOS), (x + (big - small) // 2, big + 20))
        dr.text((x + 4, big + small + 30), name, fill=(40, 20, 10, 255))
    sheet.save(os.path.join(CANDS, id_ + "_review.png"))


def candidates():
    os.makedirs(CANDS, exist_ok=True)
    for id_ in ROCKS:
        if ONLY and id_ not in ONLY:
            continue
        cands = []
        for k in range(SEEDS):
            c = finish(paint(id_, k), ROCKS[id_][2])
            c.save(os.path.join(CANDS, "%s_c%d.png" % (id_, k)))
            cands.append(c)
        review(id_, cands)
        ga.log("rocks: %s %d candidates -> %s" % (id_, len(cands), os.path.join(CANDS, id_ + "_review.png")))


def pick(picks):
    for p in picks:
        id_, k = p.split("=")
        Image.open(os.path.join(CANDS, "%s_c%s.png" % (id_, k))).save(os.path.join(OUT, id_ + ".png"))
        ga.log("rocks: picked %s c%s" % (id_, k))


if __name__ == "__main__":
    if "--pick" in ARGS:
        pick([a for a in ARGS[ARGS.index("--pick") + 1:] if "=" in a])
    else:
        candidates()
