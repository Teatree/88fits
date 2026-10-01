"""The last placeholder art (pass 42): the Wanted UI's painted slots and the boss portal in the world, on the best
model the server has, Flux.2 dev at full steps (no Turbo LoRA), several seeds each, picked by eye.

  portal_gate  the portal a boss leaves behind: a sandstone moon gate, painted like the scenery (a billboard; the game
               swirls the round opening) -> game/art/sprites/props/boss_portal.png
  portal       the stage-clear Continue card: the same gate with the vortex painted in (an edit of the picked gate)
               -> game/art/ui/wanted/portal.png
  strongbox    the stage-clear Extract card: the world's Strongbox, lid open, full of gold (an edit of st_gold_bank)
               -> game/art/ui/wanted/strongbox.png
  stranger     the Stranger's portrait, holding out an offering (an edit of st_hooded_figure) -> .../stranger.png
  mirror       the Mirror: a brass frame, dark glass, two eyes looking out -> .../mirror.png

    python tools/gen_ui_art.py [--only portal_gate,mirror] [--seeds=4] [--first-seed=7]
        -> tools/dl/ui_art/<slot>_<n>.png (finished) + <slot>_<n>_raw.png + review_<slot>.png
    python tools/gen_ui_art.py --pick portal_gate=2 strongbox=0 ...      -> installs the picked ones

Flux.2 dev and its 18 GB text encoder do not fit the server's RAM twice: after every render the models are released
(comfy.release_models), as gen_props does."""
import io
import json
import os
import sys
import time

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402
from gen_props import mute, hole_fraction, NO_FACE  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tools", "dl", "ui_art")
RAW_PROPS = os.path.join(REPO, "tools", "dl", "ai_raw_props")
UI_DIR = os.path.join(REPO, "game", "art", "ui", "wanted")
PROPS_DIR = os.path.join(REPO, "game", "art", "sprites", "props")
STEPS = 28

EDIT = ("Keep exactly the same object, shapes, colours, materials and art style as the reference image; change only what is "
        "described. ")

SLOTS = {
    "portal_gate": {
        "prompt": lambda bg: ga.styled(
            "a desert prop for a game: an ancient desert moon gate, a thick free-standing wall of weathered red sandstone blocks "
            "with one big perfectly round opening through its middle, the round opening completely empty so you can see straight "
            "through it, small glowing green runes carved in a ring around the opening, standing on a low stone step on the "
            "ground" + NO_FACE,
            "Seen from the front at eye level, the whole gate visible, its base resting on the floor line, no ground patch, no "
            "cast shadow, nothing else in the frame.", bg),
        "ref": "anchor", "size": (1024, 1024), "screen": "blue", "finish": ("prop", 384), "out": os.path.join(PROPS_DIR, "boss_portal.png"),
    },
    "portal": {
        "prompt": lambda bg: (EDIT + "The round opening of this stone gate is now filled with a swirling glowing green magic "
                              "vortex spiralling into a bright pale green centre, with a few small green sparks drifting out of "
                              "it. The whole gate stays visible, seen from the front. " + ga.STYLE + ". " + bg + "."),
        "ref": "pick:portal_gate", "size": (1024, 1024), "screen": "blue", "finish": ("ui", (300, 300), "center", 0.96),
        "out": os.path.join(UI_DIR, "portal.png"),
    },
    "strongbox": {
        "prompt": lambda bg: (EDIT + "This wooden treasure chest with dark iron bands and the round gold coin emblem, without the "
                              "balloon and without the string: its lid is thrown open and the chest is overflowing with a big "
                              "heap of shiny gold coins, a few coins spilling over the front edge onto the floor. Seen from the "
                              "front and a little above. " + NO_FACE + ". " + ga.STYLE + ". " + bg + "."),
        "ref": "raw:st_gold_bank", "size": (1024, 1024), "screen": "green", "finish": ("ui", (300, 300), "center", 0.94),
        "out": os.path.join(UI_DIR, "strongbox.png"),
    },
    "stranger": {
        "prompt": lambda bg: (EDIT + "This same hooded figure in the ragged dark violet cloak, now seen closer, from the waist up, "
                              "facing the viewer: both hands have come out of the long sleeves and reach towards the viewer, "
                              "cupping a small glowing golden light in the open palms as an offering. The deep hood still hides "
                              "the whole face in black shadow, with only a faint violet glow inside it; thin pale hands, no face "
                              "visible at all. " + ga.STYLE + ". " + bg + "."),
        "ref": "raw:st_hooded_figure", "size": (1344, 1056), "screen": "green", "finish": ("ui", (1066, 838), "bottom", 0.97),
        "out": os.path.join(UI_DIR, "stranger.png"),
    },
    "mirror": {
        "prompt": lambda bg: ga.styled(
            "an ornate antique round wall mirror in a thick polished brass frame with carved scrollwork and small rivets, the "
            "glass dark and smoky like a night sky, and deep inside the dark glass two glowing amber eyes looking out at the "
            "viewer, nothing else visible in the glass",
            "Seen straight from the front, the whole round mirror visible and centred, nothing else in the frame.", bg),
        "ref": "anchor", "size": (1024, 1024), "screen": "green", "finish": ("ui", (420, 420), "center", 0.98),
        "out": os.path.join(UI_DIR, "mirror.png"),
    },
}


def log(*a):
    print(*a, flush=True)


def raw_of_prop(pid):
    """The raw render the shipped painting of a structure came from (the highest-quality copy of it): of the attempts
    cached for it, the one whose silhouette matches the shipped painting best; the painting itself on its screen colour
    when no raw one is left."""
    import numpy as np
    shipped = Image.open(os.path.join(PROPS_DIR, pid + ".png")).convert("RGBA")
    sa = np.asarray(artkit.crop_alpha(shipped).getchannel("A").resize((64, 64))).astype(np.float32) / 255.0
    best, best_d = None, 1e9
    for f in sorted(os.listdir(RAW_PROPS)):
        if not (f.startswith(pid + "_") and f.endswith(".png")) or "_off" in f:
            continue
        rest = f[len(pid) + 1:-4]
        if not rest.isdigit():
            continue
        img = Image.open(os.path.join(RAW_PROPS, f)).convert("RGB")
        a = np.asarray(artkit.crop_alpha(artkit.key_background(img)).getchannel("A").resize((64, 64))).astype(np.float32) / 255.0
        d = float(np.abs(a - sa).mean())
        if d < best_d:
            best, best_d = img, d
    if best is not None:
        log("  %s: the raw render closest to the shipped painting (%.3f)" % (pid, best_d))
        return best
    bg = Image.new("RGBA", shipped.size, (0, 255, 0, 255))
    bg.alpha_composite(shipped)
    return bg.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def reference(spec):
    r = spec["ref"]
    if r == "anchor":
        return ga.ensure_anchor_uploaded()
    if r.startswith("raw:"):
        img = raw_of_prop(r[4:])
        return [comfy.upload_pil(img, "uiart_ref_" + r[4:] + ".png")]
    if r.startswith("pick:"):
        src = os.path.join(OUT, "picked_%s_raw.png" % r[5:])
        if not os.path.exists(src):
            raise SystemExit("pick %s first (python tools/gen_ui_art.py --pick %s=N)" % (r[5:], r[5:]))
        return [comfy.upload_pil(Image.open(src).convert("RGB"), "uiart_ref_" + r[5:] + ".png")]
    raise ValueError(r)


def finish(slot, raw):
    spec = SLOTS[slot]
    keyed = artkit.punch(artkit.key_background(raw))
    kind = spec["finish"][0]
    if kind == "prop":
        cell = spec["finish"][1]
        cell_img, _ = ga.finish(raw, cell, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
        return mute(cell_img), keyed
    _, box, align, fill = spec["finish"]
    fig = artkit.crop_alpha(keyed)
    k = min(box[0] * fill / fig.width, box[1] * fill / fig.height)
    fig = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", box, (0, 0, 0, 0))
    y = (box[1] - fig.height) // 2 if align == "center" else box[1] - fig.height
    out.alpha_composite(fig, ((box[0] - fig.width) // 2, y))
    return out, keyed


def paint(slot, seeds, first):
    spec = SLOTS[slot]
    bg = ga.BG_BLUE if spec["screen"] == "blue" else ga.BG_GREEN
    prompt = spec["prompt"](bg)
    refs = reference(spec)
    os.makedirs(OUT, exist_ok=True)
    made = []
    for n in range(seeds):
        seed = first + n * 131
        t0 = time.time()
        imgs, _ = comfy.run(comfy.flux2_dev(prompt, seed, spec["size"][0], spec["size"][1], refs=refs, steps=STEPS, guidance=4.0,
                                            turbo=False, prefix="88fits/uiart_" + slot))
        raw = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        raw.save(os.path.join(OUT, "%s_%d_raw.png" % (slot, n)))
        done, keyed = finish(slot, raw)
        done.save(os.path.join(OUT, "%s_%d.png" % (slot, n)))
        holes = hole_fraction(artkit.crop_alpha(keyed))
        made.append((done, holes))
        log("  %s #%d seed %d  %.0fs  holes %.3f  %s" % (slot, n, seed, time.time() - t0, holes, comfy.release_models()))
    json.dump({"prompt": prompt, "seeds": [first + n * 131 for n in range(seeds)], "steps": STEPS, "model": "flux2 dev"},
              open(os.path.join(OUT, slot + ".json"), "w", encoding="utf-8"), indent=1)
    review(slot, made)


def review(slot, made):
    """The candidates side by side on the UI's paper (and on dark plum for the Stranger), numbered, to pick by eye."""
    pad = 20
    w = max(m[0].width for m in made)
    h = max(m[0].height for m in made)
    k = min(1.0, 700.0 / h)
    tw, th = int(w * k), int(h * k)
    paper = (48, 30, 38) if slot == "stranger" else (243, 230, 200)
    sheet = Image.new("RGB", (len(made) * (tw + pad) + pad, th + 2 * pad + 44), paper)
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(os.path.join(REPO, "game", "ui", "fonts", "AlfaSlabOne-Regular.ttf"), 30)
    except Exception:
        font = ImageFont.load_default()
    for i, (img, holes) in enumerate(made):
        x = pad + i * (tw + pad)
        t = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
        sheet.paste(t, (x, pad), t)
        dr.rectangle([x - 1, pad - 1, x + tw, pad + th], outline=(120, 100, 80), width=1)
        dr.text((x + 6, pad + th + 6), "#%d  holes %.3f" % (i, holes), fill=(200, 180, 150) if slot == "stranger" else (36, 27, 20), font=font)
    sheet.save(os.path.join(OUT, "review_%s.png" % slot))
    log("  review: " + os.path.join(OUT, "review_%s.png" % slot))


def opening(cell_rgba):
    """The gate's round opening in its finished painting: the biggest see-through region the stone encloses, as
    {x, y (from the top), r} fractions of the square (the game swirls the vortex there)."""
    import numpy as np
    from scipy import ndimage
    a = np.asarray(cell_rgba.getchannel("A")) > 127
    holes = ndimage.binary_fill_holes(a) & ~a
    lab, n = ndimage.label(holes)
    if n == 0:
        return {"x": 0.5, "y": 0.48, "r": 0.2}
    sizes = ndimage.sum(holes, lab, range(1, n + 1))
    ys, xs = np.nonzero(lab == int(np.argmax(sizes)) + 1)
    w, h = cell_rgba.size
    r = min(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) * 0.5
    return {"x": round(float(xs.mean()) / w, 4), "y": round(float(ys.mean()) / h, 4), "r": round(float(r) / w, 4)}


def pick(pairs):
    for p in pairs:
        slot, n = p.split("=")
        src = os.path.join(OUT, "%s_%s.png" % (slot, n))
        dst = SLOTS[slot]["out"]
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.open(src).save(dst)
        # the raw render too, for the edits that start from this one (the card's portal from the gate)
        Image.open(os.path.join(OUT, "%s_%s_raw.png" % (slot, n))).save(os.path.join(OUT, "picked_%s_raw.png" % slot))
        log("installed %s -> %s" % (src, dst))
        if slot == "portal_gate":
            cfg = {"height": 3.6, "cell": SLOTS[slot]["finish"][1], "portal": opening(Image.open(src).convert("RGBA"))}
            with open(os.path.join(PROPS_DIR, "boss_portal.json"), "w", encoding="utf-8", newline="\n") as f:
                json.dump(cfg, f, indent=1)
            log("  the opening: %s" % cfg["portal"])


def main():
    args = sys.argv[1:]
    if "--pick" in args:
        pick(args[args.index("--pick") + 1:])
        return
    only = list(SLOTS.keys())
    seeds, first = 4, 7
    for i, a in enumerate(args):
        if a == "--only" and i + 1 < len(args):
            only = args[i + 1].split(",")
        elif a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        elif a.startswith("--seeds="):
            seeds = int(a.split("=")[1])
        elif a.startswith("--first-seed="):
            first = int(a.split("=")[1])
    for slot in only:
        log("painting " + slot)
        paint(slot, seeds, first)


if __name__ == "__main__":
    main()
