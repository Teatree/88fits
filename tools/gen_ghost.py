"""Pass 120 (lane GHOST): the Undertaker's Shovel's floating ghost, one painting for every hero (Garry: "instead of the
ghost being Player's hero let's make it an actual floating ghost ... It's a 2 sided sprite and it's mostly staying
still"). A FRONT painting (Flux.2 Klein, the style anchor as its reference, several seeds, picked by eye) and a BACK
painting made as a Klein edit of the chosen front (the front as its reference, so the two match), each keyed off the
green screen and fitted into a 256 px cell with its tail's tip on the floor line, the back at the front's own height.
core/systems/Graveyard.gd shows the front while the ghost comes across or towards the camera and the back while it goes
away (a paper turn between them).

  python tools/gen_ghost.py front [--seeds 2] [--force]          # front candidates (every subject x seeds) + a sheet
  python tools/gen_ghost.py back --front N [--seeds 4] [--force] # back candidates edited from front candidate N + a sheet
  python tools/gen_ghost.py --pick-front N --pick-back M [--mirror-back]   # the pair -> content/passives/undertakers_shovel/
                                                                           # (--mirror-back: the back flipped, its tail on the far side)
Outputs: tools/dl/p121/GHOST2/raw/ (renders), tools/dl/p121/GHOST2/cands/ (fitted cells, review sheets).

Pass 121 (lane GHOST2; Garry: "Ghost is awful looking. Make it more ghost looking. No clothing. Like a regular ghost with
minimal facial features."): the cowboy hat and the bandana are gone. Four plain-ghost subjects (a round head flowing into a
sheet-like body that thins into a wispy tail, no legs; two dark hollow eyes, at most a small dark mouth; one with soft
wisp arms, one with a hem of three wisps), the back prompt without the hat and the knot. Pass 120's renders stay in
tools/dl/p120/GHOST/.
"""
import io
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
RAW = os.path.join(REPO, "tools", "dl", "p121", "GHOST2", "raw")
CANDS = os.path.join(REPO, "tools", "dl", "p121", "GHOST2", "cands")
DST = os.path.join(REPO, "game", "content", "passives", "undertakers_shovel")
FRONT_NAME = "undertakers_shovel_ghost_front.png"
BACK_NAME = "undertakers_shovel_ghost_back.png"
CELL = 256
FILL = 0.92
OUTLINE = (34, 44, 70, 255)
SEED = 12001
SAND = (226, 190, 140, 255)
# the game's look (params.grave.ghost_tint, ghost_mix, ghost_alpha) for the review sheet's preview
TINT = (0x7f, 0xe6, 0xff)
MIX = 0.45
ALPHA = 0.85

# pass 121: a plain ghost, nothing worn (Garry: "No clothing. Like a regular ghost with minimal facial features")
HEAD = ("a classic plain floating ghost and nothing else: a smooth round dome-shaped head that flows with no neck into a soft "
        "draped sheet-like body")
TAIL = "the body narrowing below into one long wispy tail that curls to one side and thins to a soft point, no legs, no feet"
NO_ARMS = "no arms, no hands"
WISP_ARMS = ("two short soft wispy arm-flaps flowing out of its sides like the loose ends of a sheet, tapering to points, no "
             "hands, no fingers")
HEM = ("the sheet's bottom hem breaking into three soft wavy wisps that trail away below and thin to points, no legs, no "
       "feet, no arms, no hands")
EYES = "its face only two dark hollow oval eyes set level side by side, no nose, no mouth, no eyebrows"
EYES_MOUTH = ("its face only two dark hollow oval eyes set level side by side and a small dark round mouth below them, no "
              "nose, no eyebrows")
BARE = "It is completely plain and bare: nothing worn, nothing held, no clothing and no accessories"
SKIN = ("Pale white all over with soft cool blue-grey cel shading down its sides and under its head, a faint pale cyan glow "
        "along its edges")
SUBJECTS = [
    HEAD + ", " + TAIL + ", " + NO_ARMS + ", " + EYES + ". " + BARE + ". " + SKIN,
    HEAD + ", " + TAIL + ", " + NO_ARMS + ", " + EYES_MOUTH + ". " + BARE + ". " + SKIN,
    HEAD + ", " + TAIL + ", " + WISP_ARMS + ", " + EYES_MOUTH + ". " + BARE + ". " + SKIN,
    HEAD + ", " + HEM + ", " + EYES + ". " + BARE + ". " + SKIN,
]
VIEW_FRONT = ("Floating in the air, seen straight from the front, facing the viewer, upright and symmetrical, the whole ghost "
              "visible from the top of its head to the tip of its tail.")
BACK_PROMPT = ("Turn the ghost of the reference image around and show the very same ghost seen directly from behind: the smooth "
               "back of its round head flowing into its smooth sheet-like back{extra}. No face, no eyes, no mouth visible from "
               "behind. It wears nothing. Exactly the same size, proportions, colours, outline and art style as the reference "
               "image, floating, seen straight from behind, the whole ghost visible. ")
# per subject: what else the back shows
BACK_EXTRA = [", and the same long wispy tail curling to the side",
              ", and the same long wispy tail curling to the side",
              ", its two soft wispy arm-flaps at its sides and the same long wispy tail curling to the side",
              ", and the same hem of three soft wavy wisps trailing below"]

ARGS = sys.argv[1:]


def opt(name, default=None):
    if name in ARGS:
        i = ARGS.index(name)
        if i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


SEEDS = int(opt("--seeds", "2"))
FORCE = "--force" in ARGS


def _render(key, prompt, seed, refs):
    os.makedirs(RAW, exist_ok=True)
    raw = os.path.join(RAW, key + ".png")
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    t0 = time.time()
    imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=refs, prefix="88fits/p121_ghost"))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  %s seed %d %.0fs" % (key, seed, time.time() - t0))
    return img


def cool_halo(cell):
    """Pass 121: the faint glow Klein paints round the ghost lies on the green screen, so the keyer leaves it as a pale
    green band inside the outline (and a green cast on the white). Every figure pixel greener than it is blue gets its blue
    raised to its green: the band turns the pale cyan glow the ghost wants, the whites a cool white; the eyes, the blue-grey
    shading and the outline (bluer than green) are left as they are."""
    a = np.asarray(cell.convert("RGBA")).astype(np.int32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    m = (al > 0) & (g > np.maximum(r, b))
    return Image.fromarray(np.stack([r, g, np.where(m, g, b), al], -1).astype(np.uint8), "RGBA")


def finish(img, target_h=None):
    cell, _ = ga.finish(img, CELL, FILL, True, None, 0.012, target_h, OUTLINE)
    return cool_halo(cell)


def figure_h(cell):
    box = cell.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    return (box[3] - box[1]) if box else CELL


def game_look(cell):
    """The cell as the game draws it: lightness redrawn in TINT by MIX (sprite_billboard_over's ghost), ALPHA opaque."""
    rgba = cell.convert("RGBA")
    px = rgba.load()
    out = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    po = out.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            k = 0.45 + 0.75 * lum
            nr = r * (1 - MIX) + min(255, TINT[0] * k) * MIX
            ng = g * (1 - MIX) + min(255, TINT[1] * k) * MIX
            nb = b * (1 - MIX) + min(255, TINT[2] * k) * MIX
            po[x, y] = (int(nr), int(ng), int(nb), int(a * ALPHA))
    return out


def sheet(cells, labels, name):
    big, small = 300, 96
    w = len(cells) * (big + 20) + 20
    out = Image.new("RGBA", (w, big * 2 + small + 90), SAND)
    dr = ImageDraw.Draw(out)
    for i, (im, lab) in enumerate(zip(cells, labels)):
        x = 20 + i * (big + 20)
        out.alpha_composite(im.resize((big, big), Image.LANCZOS), (x, 10))
        out.alpha_composite(game_look(im).resize((big, big), Image.LANCZOS), (x, big + 20))
        out.alpha_composite(game_look(im).resize((small, small), Image.LANCZOS), (x + (big - small) // 2, big * 2 + 30))
        dr.text((x + 4, big * 2 + small + 40), lab, fill=(40, 20, 10, 255))
    os.makedirs(CANDS, exist_ok=True)
    p = os.path.join(CANDS, name)
    out.save(p)
    ga.log("ghost: sheet -> %s" % p)
    return p


def front_key(k):
    return "front_s%d_%d" % (k % len(SUBJECTS), SEED + k * 977)


def fronts():
    refs = list(ga.ensure_anchor_uploaded())
    cells, labels = [], []
    n = len(SUBJECTS) * SEEDS
    for k in range(n):
        subj = SUBJECTS[k % len(SUBJECTS)]
        prompt = ga.styled(subj, VIEW_FRONT, ga.BG_GREEN)
        img = _render(front_key(k), prompt, SEED + k * 977, refs)
        c = finish(img)
        os.makedirs(CANDS, exist_ok=True)
        c.save(os.path.join(CANDS, "front_c%d.png" % k))
        cells.append(c)
        labels.append("front c%d (subject %d)" % (k, k % len(SUBJECTS)))
    sheet(cells, labels, "front_review.png")


def backs(front_k):
    src = Image.open(os.path.join(RAW, front_key(front_k) + ".png")).convert("RGB")
    up = comfy.upload_pil(src, "p121_ghost_front_%d.png" % front_k)
    prompt = BACK_PROMPT.format(extra=BACK_EXTRA[front_k % len(SUBJECTS)]) + ga.STYLE + ". " + ga.BG_GREEN + "."
    front_cell = Image.open(os.path.join(CANDS, "front_c%d.png" % front_k))
    th = figure_h(front_cell)
    cells, labels = [front_cell], ["front c%d" % front_k]
    for j in range(SEEDS):
        s = SEED + 50000 + front_k * 131 + j * 977
        img = _render("back_f%d_%d" % (front_k, s), prompt, s, [up])
        c = finish(img, th)
        c.save(os.path.join(CANDS, "back_f%d_c%d.png" % (front_k, j)))
        cells.append(c)
        labels.append("back c%d" % j)
    sheet(cells, labels, "back_f%d_review.png" % front_k)


def pick(front_k, back_j, mirror_back=False):
    f = Image.open(os.path.join(CANDS, "front_c%d.png" % front_k))
    b = Image.open(os.path.join(CANDS, "back_f%d_c%d.png" % (front_k, back_j)))
    if mirror_back:
        # pass 121: Klein's back keeps the front's tail on the same side; a ghost turned round has it on the other
        b = b.transpose(Image.FLIP_LEFT_RIGHT)
    os.makedirs(DST, exist_ok=True)
    f.save(os.path.join(DST, FRONT_NAME))
    b.save(os.path.join(DST, BACK_NAME))
    ga.log("ghost: front c%d, back c%d -> %s" % (front_k, back_j, DST))


if __name__ == "__main__":
    if "--pick-front" in ARGS:
        pick(int(opt("--pick-front")), int(opt("--pick-back", "0")), "--mirror-back" in ARGS)
    elif ARGS and ARGS[0] == "back":
        backs(int(opt("--front", "0")))
    else:
        fronts()
