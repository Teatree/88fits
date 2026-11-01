"""Pass 120 (lane GHOST): the Undertaker's Shovel's floating ghost, one painting for every hero (Garry: "instead of the
ghost being Player's hero let's make it an actual floating ghost ... It's a 2 sided sprite and it's mostly staying
still"). A FRONT painting (Flux.2 Klein, the style anchor as its reference, several seeds, picked by eye) and a BACK
painting made as a Klein edit of the chosen front (the front as its reference, so the two match), each keyed off the
green screen and fitted into a 256 px cell with its tail's tip on the floor line, the back at the front's own height.
core/systems/Graveyard.gd shows the front while the ghost comes across or towards the camera and the back while it goes
away (a paper turn between them).

  python tools/gen_ghost.py front [--seeds 2] [--force]          # front candidates (every subject x seeds) + a sheet
  python tools/gen_ghost.py back --front N [--seeds 4] [--force] # back candidates edited from front candidate N + a sheet
  python tools/gen_ghost.py --pick-front N --pick-back M         # the pair -> content/passives/undertakers_shovel/
Outputs: tools/dl/p120/GHOST/raw/ (renders), tools/dl/p120/GHOST/cands/ (fitted cells, review sheets).
"""
import io
import os
import sys
import time

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RAW = os.path.join(REPO, "tools", "dl", "p120", "GHOST", "raw")
CANDS = os.path.join(REPO, "tools", "dl", "p120", "GHOST", "cands")
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

BODY = ("a classic floating cartoon ghost: a big round head and a soft rounded body like a draped white sheet that narrows into "
        "a long wispy curling tail instead of legs, two small stubby arms held out a little at its sides")
SKIN = "Its body pale white with soft cool blue-grey cel shading, the tail's tip curling to one side"
SUBJECTS = [
    BODY + ", big dark oval eyes and a small round open mouth, a battered old brown cowboy hat on its head and a faded red "
    "bandana tied round its neck. " + SKIN,
    BODY + ", big dark hollow oval eyes and a small surprised round mouth, a battered old brown cowboy hat with a dented crown "
    "pulled down a little on its head. " + SKIN,
    BODY + ", big dark oval eyes above a faded red bandana tied over the lower half of its face like an outlaw's mask, a "
    "battered old brown cowboy hat on its head. " + SKIN,
]
VIEW_FRONT = ("Floating in the air, seen straight from the front, facing the viewer, a symmetrical pose, the whole ghost visible "
              "from the hat to the tail's tip.")
BACK_PROMPT = ("Turn the ghost of the reference image around and show the very same ghost seen directly from behind: the back "
               "of its round head and the back of its battered brown cowboy hat, {neck}its smooth sheet-like back, its stubby "
               "arms at its sides and the same long wispy curling tail. No face, no eyes, no mouth visible. Exactly the same "
               "size, proportions, colours, outline and art style as the reference image, floating, seen straight from behind, "
               "the whole ghost visible. ")
NECK = ["the knot of its red bandana at the back of its neck, ", "", "the knot of its red bandana mask at the back of its head, "]

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
    imgs, _ = comfy.run(comfy.klein(prompt, seed, 1024, 1024, refs=refs, prefix="88fits/p120_ghost"))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  %s seed %d %.0fs" % (key, seed, time.time() - t0))
    return img


def finish(img, target_h=None):
    cell, _ = ga.finish(img, CELL, FILL, True, None, 0.012, target_h, OUTLINE)
    return cell


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
    up = comfy.upload_pil(src, "p120_ghost_front_%d.png" % front_k)
    prompt = BACK_PROMPT.format(neck=NECK[front_k % len(SUBJECTS)]) + ga.STYLE + ". " + ga.BG_GREEN + "."
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


def pick(front_k, back_j):
    f = Image.open(os.path.join(CANDS, "front_c%d.png" % front_k))
    b = Image.open(os.path.join(CANDS, "back_f%d_c%d.png" % (front_k, back_j)))
    os.makedirs(DST, exist_ok=True)
    f.save(os.path.join(DST, FRONT_NAME))
    b.save(os.path.join(DST, BACK_NAME))
    ga.log("ghost: front c%d, back c%d -> %s" % (front_k, back_j, DST))


if __name__ == "__main__":
    if "--pick-front" in ARGS:
        pick(int(opt("--pick-front")), int(opt("--pick-back", "0")))
    elif ARGS and ARGS[0] == "back":
        backs(int(opt("--front", "0")))
    else:
        fronts()
