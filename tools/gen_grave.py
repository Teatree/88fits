"""Pass 119 (lane LEGEND_B): the Undertaker's Shovel's grave, a painted 2.5D billboard in the props' own style (Garry:
"The tombstones should spawn and despawn with an animation, not just pop in an out"; core/systems/Graveyard.gd raises
it out of the sand and sinks it again). Each candidate is a Flux.2 Klein render with two references, the style anchor
and a raw render of the signpost (weathered wood, the same line and palette), keyed off the blue screen and finished as
tools/gen_props.py finishes a prop (the fit with the base on the floor, the warm thin outline, the mute); the pick is
made by eye and written into the item's own folder (content/passives/undertakers_shovel/undertakers_shovel_grave.png),
which its params.grave.sprite names.

  python tools/gen_grave.py [--seeds 4] [--force]        # candidates + a review sheet -> tools/dl/p119/LEGEND_B/grave/
  python tools/gen_grave.py --pick N                     # candidate N -> the item's folder
"""
import io
import os
import sys
import time

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402
import gen_props as gp  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
CANDS = os.path.join(REPO, "tools", "dl", "p119", "LEGEND_B", "grave")
DST = os.path.join(REPO, "game", "content", "passives", "undertakers_shovel", "undertakers_shovel_grave.png")
STYLE_REF = "signpost_24.png"
CELL = 256
SEED = 11901
SUBJECTS = [
    "a fresh desert grave: a weathered wooden grave cross of two rough planks lashed with rope, planted upright in a low "
    "long mound of freshly dug brown earth, a few small stones along the mound's foot" + gp.NO_FACE,
    "a fresh desert grave: a small rounded grey stone headstone with a carved cross on its face, a little cracked and "
    "chipped, standing at the end of a low mound of freshly dug brown earth" + gp.NO_FACE,
]

ARGS = sys.argv[1:]
SEEDS = int(ARGS[ARGS.index("--seeds") + 1]) if "--seeds" in ARGS else 4
FORCE = "--force" in ARGS


def render(k):
    subj = SUBJECTS[k % len(SUBJECTS)]
    s = SEED + k * 977
    os.makedirs(RAW, exist_ok=True)
    raw = os.path.join(RAW, "grave_%d.png" % s)
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    prompt = ("Using exactly the same art style, rendering, line art, cel shading, palette, lighting from the upper left and "
              "level of detail as the reference images, draw a new desert prop for the same game: " + subj + ". "
              "Seen from the front and a little above, the whole object visible, its base resting on the floor line, no ground "
              "patch round it, no cast shadow, nothing else in the frame. " + ga.STYLE + ". " + ga.BG_BLUE + ". Do not copy the "
              "reference objects: this is a different object of the same world.")
    refs = list(ga.ensure_anchor_uploaded())
    p = os.path.join(RAW, STYLE_REF)
    if os.path.exists(p):
        refs.append(comfy.upload_pil(Image.open(p).convert("RGB"), "p119_grave_ref.png"))
    t0 = time.time()
    imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/p119_grave"))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  grave c%d seed %d %.0fs" % (k, s, time.time() - t0))
    return img


def finish(img):
    cell_img, _ = ga.finish(img, CELL, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
    return gp.mute(cell_img)


def candidates():
    os.makedirs(CANDS, exist_ok=True)
    cands = []
    for k in range(SEEDS):
        c = finish(render(k))
        c.save(os.path.join(CANDS, "grave_c%d.png" % k))
        cands.append(c)
    big, small = 300, 110
    sheet = Image.new("RGBA", (len(cands) * (big + 20) + 20, big + small + 70), (226, 190, 140, 255))
    dr = ImageDraw.Draw(sheet)
    for i, im in enumerate(cands):
        x = 20 + i * (big + 20)
        sheet.alpha_composite(im.resize((big, big), Image.LANCZOS), (x, 10))
        sheet.alpha_composite(im.resize((small, small), Image.LANCZOS), (x + (big - small) // 2, big + 20))
        dr.text((x + 4, big + small + 30), "c%d" % i, fill=(40, 20, 10, 255))
    sheet.save(os.path.join(CANDS, "grave_review.png"))
    ga.log("grave: %d candidates -> %s" % (len(cands), os.path.join(CANDS, "grave_review.png")))


def pick(k):
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    Image.open(os.path.join(CANDS, "grave_c%d.png" % k)).save(DST)
    ga.log("grave: picked c%d -> %s" % (k, DST))


if __name__ == "__main__":
    if "--pick" in ARGS:
        pick(int(ARGS[ARGS.index("--pick") + 1]))
    else:
        candidates()
