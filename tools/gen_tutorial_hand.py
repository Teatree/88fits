"""Pass 141 (lane SMALL; Garry: "Tutorial Finger - get a normal looking finger please, this looks bad."): the tutorial's
pointing hand, a painted picture in place of the white glove ui/wanted/WHighlight.gd drew in code. Each candidate is a
Flux.2 Klein render with the style anchor as its reference, on the green screen, keyed, cropped and outlined; three
subjects (a skin-toned hand with a shirt cuff, a white cartoon glove, the skin hand again with its three curled fingers
named), --seeds each (candidate k paints subject k // seeds). The pick is made by eye at full size (five fingers, a real
thumb, the wrist cut cleanly) and installed at game/art/ui/tutorial/hand.png; the tool prints the fingertip's pixel (the
top of the pointing finger), which WHighlight's HAND_TIP_PX holds. Pass 141 picked c8 (seed 21917).

  python tools/gen_tutorial_hand.py [--seeds 3] [--force]   # candidates + review sheets -> tools/dl/p141/SMALL/hand/
  python tools/gen_tutorial_hand.py --pick N                # candidate N -> game/art/ui/tutorial/hand.png (then --import)
"""
import io
import json
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CANDS = os.path.join(REPO, "tools", "dl", "p141", "SMALL", "hand")
DST = os.path.join(REPO, "game", "art", "ui", "tutorial", "hand.png")
## the installed picture's height in px (WHighlight draws it at about half that on the 1080 canvas), its outline
HEIGHT = 384
OUTLINE_PX = 4
OUTLINE = (20, 16, 34, 255)
SEED = 14101
COMMON = ("Mobile game tutorial pointer: one single cartoon hand and nothing else, upright, the pointing index finger "
          "vertical with its tip at the top, five fingers in all with a real thumb, natural proportions, a thick clean "
          "dark outline of even weight around the whole silhouette, cel shading with one soft shadow tone and one "
          "highlight, smooth clean surfaces with no texture, the whole hand and its cuff visible with a margin round it, "
          "no arm beyond the cuff, no text, no arrow, no tap marks, no sparkles")
SUBJECTS = [
    "a right hand seen from the back, pointing: the index finger stretched straight up with a short rounded fingernail "
    "at its tip, the middle, ring and little fingers curled down tightly into the palm, the thumb folded in over the "
    "curled middle finger, smooth light warm peach skin, a slim wrist ending in a short neat white shirt cuff cut "
    "straight across at the bottom",
    "a white cartoon glove on a right hand seen from the back, pointing: the index finger stretched straight up, the "
    "middle, ring and little fingers curled down into the palm, the thumb folded in over them, three short dark stitch "
    "lines on the back of the glove, a rolled white cuff at the wrist cut straight across at the bottom",
    "a right hand seen from the back, pointing: the index finger stretched straight up with a short rounded fingernail "
    "at its tip, the middle, ring and little fingers curled down into the palm so that their three curled fingers show "
    "side by side to the right of the index finger, stepping down to the smallest, the thumb resting along the left side "
    "of the hand with its nail showing, smooth light warm peach skin, a slim wrist ending in a short neat white shirt cuff "
    "cut straight across at the bottom",
]
## the review's label for each subject
LABELS = ["skin", "glove", "skin 3 knuckles"]

ARGS = sys.argv[1:]
SEEDS = int(ARGS[ARGS.index("--seeds") + 1]) if "--seeds" in ARGS else 3
FORCE = "--force" in ARGS


def render(k):
    """Candidate k's raw render (subject k // SEEDS), cached in CANDS."""
    subj = SUBJECTS[(k // SEEDS) % len(SUBJECTS)]
    s = SEED + k * 977
    os.makedirs(CANDS, exist_ok=True)
    raw = os.path.join(CANDS, "raw_c%d_%d.png" % (k, s))
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    prompt = ("Using the same line art, cel shading, palette and lighting from the upper left as the reference image, draw "
              "a new picture for the same game: " + subj + ". " + COMMON + ". " + ga.BG_GREEN + ". Do not draw any of the "
              "reference's characters or objects.")
    refs = list(ga.ensure_anchor_uploaded())
    t0 = time.time()
    imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/p141_hand"))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  hand c%d seed %d %.0fs" % (k, s, time.time() - t0))
    return img


def finish(img):
    """Keyed (the cuff's foot kept whole), lifted, cropped, HEIGHT tall, outlined."""
    keyed = artkit.punch(artkit.key_background(img, cut_shadow=False))
    keyed = artkit.crop_alpha(keyed, pad=0)
    sc = float(HEIGHT - 2 * OUTLINE_PX - 4) / max(1, keyed.height)
    w, h = max(1, int(round(keyed.width * sc))), max(1, int(round(keyed.height * sc)))
    small = keyed.resize((w, h), Image.LANCZOS)
    pad = OUTLINE_PX + 2
    canvas = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(small, (pad, pad))
    return artkit.add_outline(canvas, OUTLINE_PX, OUTLINE)


def fingertip(img):
    """The top of the pointing finger in px: the topmost opaque row, the middle of the opaque run there, a few px in."""
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 128)
    if len(ys) == 0:
        return [img.width * 0.5, 0.0]
    y0 = int(ys.min())
    band = xs[ys <= y0 + 10]
    return [round(float(band.mean()), 1), float(y0 + OUTLINE_PX + 3)]


def candidates():
    os.makedirs(CANDS, exist_ok=True)
    n = SEEDS * len(SUBJECTS)
    cands = []
    for k in range(n):
        c = finish(render(k))
        c.save(os.path.join(CANDS, "hand_c%d.png" % k))
        tip = fingertip(c)
        json.dump({"tip": tip, "size": [c.width, c.height]}, open(os.path.join(CANDS, "hand_c%d.json" % k), "w",
                  encoding="utf-8", newline="\n"))
        cands.append((c, tip))
    # the review: each at full size on the UI's dark blue and on paper, its fingertip marked; then turned as in play
    cw = max(c.width for c, _ in cands) + 30
    sheet = Image.new("RGBA", (n * cw + 20, 2 * (HEIGHT + 30) + HEIGHT + 60), (40, 40, 48, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (im, tip) in enumerate(cands):
        x = 20 + i * cw
        for row, bg in enumerate([(24, 34, 78, 255), (236, 222, 196, 255)]):
            y = 30 + row * (HEIGHT + 30)
            dr.rectangle((x - 6, y - 6, x + im.width + 6, y + im.height + 6), fill=bg)
            sheet.alpha_composite(im, (x, y))
            dr.ellipse((x + tip[0] - 4, y + tip[1] - 4, x + tip[0] + 4, y + tip[1] + 4), outline=(255, 0, 0, 255), width=2)
        turned = im.rotate(34, resample=Image.BICUBIC, expand=True).resize((im.width // 2 + 40, im.height // 2 + 60), Image.LANCZOS)
        sheet.alpha_composite(turned, (x, 30 + 2 * (HEIGHT + 30)))
        dr.text((x, 8), "c%d (%s)" % (i, LABELS[(i // SEEDS) % len(LABELS)]), fill=(255, 255, 255, 255))
    p = os.path.join(CANDS, "hand_review.png")
    sheet.save(p)
    ga.log("hand: %d candidates -> %s" % (n, p))


def pick(k):
    src = os.path.join(CANDS, "hand_c%d.png" % k)
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    im = Image.open(src).convert("RGBA")
    im.save(DST)
    tip = fingertip(im)
    ga.log("hand: picked c%d -> %s (%d x %d), fingertip px %s: WHighlight.HAND_TIP_PX" % (k, DST, im.width, im.height, tip))


if __name__ == "__main__":
    if "--pick" in ARGS:
        pick(int(ARGS[ARGS.index("--pick") + 1]))
    else:
        candidates()
