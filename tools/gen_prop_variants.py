"""Pass 83 (lane SCENE; Garry: "add some variation to our environment art - a variant of agave.png, barrel_cactus.png,
ocotillo.png, boulder.png, desert_bush.png, dead_shrub, (2 more joshua_tree.png) and another small bushlike thing"):
variants of the painted props, in the very style of the originals. Each candidate is a Flux.2 Klein render with two
references, the style anchor and the original prop's own raw render (so the line, the shading and the palette carry
over), keyed off the same screen, finished exactly as tools/gen_props.py finishes a prop (the fit, the warm thin
outline, the mute), and laid on a review sheet; the pick is made by eye and written next to the original with its
props.json entry (`variant_of` names the original: PropField mixes it in wherever the map places the original).

  python tools/gen_prop_variants.py [--only agave_b,...] [--seeds 4] [--force]      # candidates + review sheets
  python tools/gen_prop_variants.py --pick agave_b=2 boulder_b=0 ...                  # the picks -> game/art/sprites/props

Candidates: tools/dl/p83/SCENE/variants/<id>_c<k>.png (finished cells), review sheets <id>_review.png (each candidate on
sand-coloured ground at the size it shows in a run and twice that), raw renders in tools/dl/ai_raw_props/."""
import io
import json
import os
import sys
import time

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402
import gen_props as gp  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(REPO, "game", "art", "sprites", "props")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_props")
CANDS = os.path.join(REPO, "tools", "dl", "p83", "SCENE", "variants")

NO_FACE = gp.NO_FACE
# id: (base id or None for a new kind, the raw render of the original used as the style reference, subject, height m,
#      radius m, cell px, first seed, screen)
VARIANTS = {
    "agave_b": ("agave", "agave_15.png",
                "a squat compact agave rosette like an artichoke: many short, broad, thick triangular leaves pointing upwards and "
                "overlapping tightly from the ground, silvery blue-grey, each tipped with a dark red-brown spine" + NO_FACE, 1.3, 0.0, 192, 8401, "green"),
    "barrel_cactus_b": ("barrel_cactus", "barrel_cactus_13.png",
                        "a cluster of two fat round ribbed green barrel cacti side by side, one big and one small, with long curved red "
                        "hooked spines and a crown of yellow flowers on the big one" + NO_FACE, 1.1, 0.25, 192, 8311, "blue"),
    "ocotillo_b": ("ocotillo", "ocotillo_37.png",
                   "a sparse ocotillo plant: only six or seven very long thin thorny whip-like stems leaning far out from one point on the "
                   "ground in a wide open V, the stems wrapped in small bright green leaves, a red flower spike on the tips of just two "
                   "stems, lots of empty space between the stems" + NO_FACE, 3.2, 0.15, 256, 8621, "blue"),
    "boulder_b": ("boulder", "boulder_20.png",
                  "a balanced rock: a big rounded sandstone boulder resting on top of a shorter, narrower sandstone pedestal rock, "
                  "layered tan and orange bands, a few small stones at the foot" + NO_FACE, 2.8, 0.62, 384, 8531, "blue"),
    "desert_bush_b": ("desert_bush", "desert_bush_34.png",
                      "a round dense desert sage bush in full bloom, covered all over in masses of bright violet-purple flowers, small silvery "
                      "grey-green leaves showing between them" + NO_FACE, 1.3, 0.0, 192, 8641, "green"),
    "dead_shrub_b": ("dead_shrub", "dead_shrub_16.png",
                     "a low dry tumble of dead desert brush: a loose wide mound of thin dry twigs and dead grass stalks, no trunk, many thin "
                     "stems straight from the ground, sun-bleached tan and pale grey, wider than it is tall" + NO_FACE, 1.2, 0.0, 192, 8551, "blue"),
    "joshua_tree_b": ("joshua_tree", None,
                      "a tall slender joshua tree: one tall straight trunk covered all the way down in a shaggy skirt of dry dead brown "
                      "leaves, splitting only at the very top into two short branches, each ending in one big spiky round green leaf ball, "
                      "like a tall thin letter Y" + NO_FACE, 4.6, 0.22, 384, 8561, "blue"),
    "joshua_tree_c": ("joshua_tree", "joshua_tree_32.png",
                      "an old wide joshua tree with a thick shaggy trunk and many crooked twisting branches spreading out to both sides, a broad "
                      "crown of many spiky green leaf balls, one long branch drooping low" + NO_FACE, 4.6, 0.22, 384, 8371, "blue"),
    # a new kind for the bush patches: a clump of desert bunchgrass (brittlebush, the first try, kept as a candidate)
    "desert_grass": (None, "creosote_bush_35.png",
                     "a clump of desert bunchgrass: a fountain of many thin tall pale golden dry grass blades springing up and arching out from "
                     "one tuft on the ground, a few feathery seed heads on top" + NO_FACE, 1.1, 0.0, 192, 8591, "blue"),
    "brittlebush": (None, "desert_bush_34.png",
                    "a small round brittlebush: a low dome of soft silvery grey-green leaves, covered on top by many bright yellow daisy "
                    "flowers on thin bare stems" + NO_FACE, 1.0, 0.0, 192, 8381, "blue"),
}

ARGS = sys.argv[1:]
ONLY = None
SEEDS = 4
FORCE = "--force" in ARGS
for a in ARGS:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
    elif a.startswith("--seeds="):
        SEEDS = int(a.split("=", 1)[1])
if "--only" in ARGS:
    ONLY = ARGS[ARGS.index("--only") + 1].split(",")
if "--seeds" in ARGS:
    SEEDS = int(ARGS[ARGS.index("--seeds") + 1])


def finish(img, cell):
    """gen_props' finish: the fit, the warm thin outline, the mute."""
    cell_img, _ = ga.finish(img, cell, 0.9, True, None, 0.007, None, (70, 46, 30, 230))
    return gp.mute(cell_img)


def render(id_, row, k):
    base, ref_raw, subject, height, radius, cell, seed, screen = row
    os.makedirs(RAW, exist_ok=True)
    s = seed + k * 977
    raw = os.path.join(RAW, "%s_%d.png" % (id_, s))
    if os.path.exists(raw) and not FORCE:
        return Image.open(raw).convert("RGB")
    bg = ga.BG_BLUE if screen == "blue" else ga.BG_GREEN
    prompt = ("Using exactly the same art style, rendering, line art, cel shading, palette, lighting from the upper left and "
              "level of detail as the reference images, draw a new desert prop for the same game: " + subject + ". "
              "Seen from the front at eye level, the whole object visible, its base resting on the floor line, no ground patch, "
              "no cast shadow, nothing else in the frame. " + ga.STYLE + ". " + bg + ". Do not copy the reference objects exactly: "
              "this is a different plant or rock of the same family.")
    refs = list(ga.ensure_anchor_uploaded())
    if ref_raw:
        ref_img = Image.open(os.path.join(RAW, ref_raw)).convert("RGB")
        refs.append(comfy.upload_pil(ref_img, "p83_" + id_ + "_ref.png"))
    t0 = time.time()
    imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/prop_" + id_))
    img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
    img.save(raw)
    ga.log("  render %-16s seed %-6d %5.0fs" % (id_, s, time.time() - t0))
    return img


def review(id_, row, cands):
    """Each candidate on sand at about its size in a run (a 192 px cell is ~1.3 m: ~110 px on the phone) and at 2x, with
    the original beside them."""
    base = row[0]
    tiles = []
    if base and os.path.exists(os.path.join(OUT, base + ".png")):
        tiles.append(("original", Image.open(os.path.join(OUT, base + ".png")).convert("RGBA")))
    for k, c in enumerate(cands):
        tiles.append(("c%d" % k, c))
    big = 300
    small = 130
    w = len(tiles) * (big + 20) + 20
    sheet = Image.new("RGBA", (w, big + small + 70), (226, 190, 140, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(tiles):
        x = 20 + i * (big + 20)
        a = im.resize((big, big), Image.LANCZOS)
        sheet.alpha_composite(a, (x, 10))
        b = im.resize((small, small), Image.LANCZOS)
        sheet.alpha_composite(b, (x + (big - small) // 2, big + 20))
        dr.text((x + 4, big + small + 30), name, fill=(40, 20, 10, 255))
    sheet.save(os.path.join(CANDS, id_ + "_review.png"))


def candidates():
    os.makedirs(CANDS, exist_ok=True)
    for id_, row in VARIANTS.items():
        if ONLY and id_ not in ONLY:
            continue
        cands = []
        for k in range(SEEDS):
            img = render(id_, row, k)
            c = finish(img, row[5])
            c.save(os.path.join(CANDS, "%s_c%d.png" % (id_, k)))
            cands.append(c)
        review(id_, row, cands)
        ga.log("variants: %s %d candidates -> %s" % (id_, len(cands), os.path.join(CANDS, id_ + "_review.png")))


def pick(picks):
    manifest_p = os.path.join(OUT, "props.json")
    manifest = json.load(open(manifest_p, encoding="utf-8"))
    for p in picks:
        id_, k = p.split("=")
        row = VARIANTS[id_]
        base, _, _, height, radius, cell, _, _ = row
        src = os.path.join(CANDS, "%s_c%s.png" % (id_, k))
        Image.open(src).save(os.path.join(OUT, id_ + ".png"))
        entry = dict(manifest.get(id_, {}))
        entry.update({"file": id_ + ".png", "height": height, "radius": radius, "cell": cell})
        if base:
            entry["variant_of"] = base
        manifest[id_] = entry
        ga.log("variants: picked %s c%s" % (id_, k))
    json.dump(manifest, open(manifest_p, "w", encoding="utf-8", newline="\n"), indent=1)


if __name__ == "__main__":
    if "--pick" in ARGS:
        pick([a for a in ARGS[ARGS.index("--pick") + 1:] if "=" in a])
    else:
        candidates()
