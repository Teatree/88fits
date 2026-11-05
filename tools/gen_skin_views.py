"""Pass 126 (lane SKINS; Garry: "Make a skin for every hero that we have, based on the ones that are selected right now"):
a skin's paintings as Klein edits of the look it starts from, view by view, so the new outfit sits on exactly the same
pose, build and size in every view.

gen_art.py turns a new front into the other views ("turn this exact character around"), which can change a hero's build
and loses what a look's own stills had (Solenne's composed side, Fadeaway's 88 on the back diagonal). Here each of the
source look's stills is the second reference and the skin's picked front (tools/gen_edit_stills.py) the first, so the
pose comes from the one and the clothes from the other. The results land in the paintings' cache as
<id>_<stills>_<view>, which gen_art.py reads for a look whose recipe says "stills": "<stills>":

    python tools/gen_edit_stills.py --id drifter --stills b --ref tools/dl/ai_raw_anime/drifter_front.png --prompt ... --seeds 4
    python tools/gen_edit_stills.py --id drifter --stills b --pick 2
    python tools/gen_skin_views.py --id drifter --stills b [--from DRI-A] --outfit "<the new outfit>" [--keep "..."]
        [--screen blue] [--views back,side,fd,bd,cheer,dead,hurt_front,...] [--force] [--first-seed N]
        -> tools/dl/ai_raw_anime/drifter_b_<view>.png + .json and tools/dl/review/drifter_b_views.png
    python tools/gen_art.py --only drifter --variant=DRI-B --skip-qa --no-import   (walks them; every still comes from the cache)

--from names the source look ("" = the hero's own paintings); its still_keys and stills are honoured, so Solenne's SOL-B
is edited from her composed side and Fadeaway's FAD-E from his 88 back diagonal. --views defaults to every view but the
front. A view already in the cache is kept unless --force names it (with --views). --first-seed moves the seeds, so a
single faulty view rolls again without touching the others.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import", "--skip-qa"]
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import comfy  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

VIEWS = ["back", "side", "fd", "bd", "cheer", "hurt_front", "hurt_back", "hurt_side", "hurt_fd", "hurt_bd", "dead"]
# what a view must keep (the edit reads the pose off its picture; the words only stop it turning the figure round)
WORDS = {
    "back": "Seen directly from behind, no face visible.",
    "side": "In strict side profile facing right.",
    "fd": "In three-quarter front view.",
    "bd": "In three-quarter back view, turned away from the viewer, no face visible.",
    "cheer": "Seen directly from behind, no face visible, jumping for joy with both arms raised high, feet together.",
    "hurt_front": "Facing the viewer, flinching in pain, feet fully visible.",
    "hurt_back": "Seen directly from behind, no face visible, flinching from a hit, feet fully visible.",
    "hurt_side": "In strict side profile facing right, flinching in pain, feet fully visible.",
    "hurt_fd": "In three-quarter front view, flinching in pain, feet fully visible.",
    "hurt_bd": "In three-quarter back view, no face visible, flinching from a hit, feet fully visible.",
    "dead": "Lying flat on the ground on the back, knocked out, limbs sprawled, the whole body visible.",
}


def opt(name, default=None):
    for i, a in enumerate(ARGS):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


def prompt_of(view, outfit, keep, bg):
    return ("The first reference image shows this character's new outfit. The second reference image shows the pose and the view. "
            "One single figure alone in the frame: redraw the figure of the second reference image in exactly the same pose, the same view, "
            "the same size and the same place in the frame, changing only the clothes to the outfit of the first reference image: "
            + outfit + ". " + WORDS.get(view, "") + (" Keep " + keep + "." if keep else "") + " " + g.STYLE + ". " + bg + ".")


def sheet(cid, stills, front_key, keys):
    W = 300
    names = [front_key] + keys
    cols = 6
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGB", (W * cols, (W + 20) * rows), (30, 30, 36))
    dr = ImageDraw.Draw(out)
    for i, k in enumerate(names):
        p = os.path.join(g.RAW, k + ".png")
        if not os.path.isfile(p):
            continue
        x, y = (i % cols) * W, (i // cols) * (W + 20)
        out.paste(Image.open(p).convert("RGB").resize((W, W), Image.LANCZOS), (x, y + 20))
        dr.text((x + 6, y + 4), k, fill=(255, 230, 140))
    d = os.path.join(REPO, "tools", "dl", "review")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "%s_%s_views.png" % (cid, stills))
    out.save(path)
    return path


def main():
    cid, stills = opt("id"), opt("stills")
    outfit = opt("outfit", "")
    if not cid or not stills:
        raise SystemExit(__doc__)
    d = json.load(open(os.path.join(REPO, "game", "content", "characters", cid, cid + ".json"), encoding="utf-8"))
    src = g.look_merged(d, opt("from", "") or "")
    bg = g.BG_BLUE if opt("screen", "blue") == "blue" else g.BG_GREEN
    keep = opt("keep", "")
    want = [v for v in (opt("views", "") or "").split(",") if v] or VIEWS
    force = "--force" in ARGS
    front_key = "%s_%s_front" % (cid, stills)
    fp = os.path.join(g.RAW, front_key + ".png")
    if not os.path.isfile(fp):
        raise SystemExit("gen_skin_views: no %s yet: paint and pick the front first (tools/gen_edit_stills.py)" % front_key)
    front_ref = comfy.upload_pil(Image.open(fp).convert("RGB"), comfy.upload_name(front_key + "_ref.png"))
    seed = g.seed_for(cid + stills + "views") + int(opt("first-seed", "0") or 0) * 7919
    keys = []
    for k, view in enumerate(VIEWS):
        key = "%s_%s_%s" % (cid, stills, view)
        keys.append(key)
        if view not in want:
            continue
        raw = os.path.join(g.RAW, key + ".png")
        if os.path.isfile(raw) and not force:
            print("gen_skin_views: %s kept" % key)
            continue
        if force:
            for ext in (".png", ".json"):
                p = os.path.join(g.RAW, key + ext)
                if os.path.isfile(p):
                    os.remove(p)
        src_key = g.hero_still_key(cid, view, src)
        sp = os.path.join(g.RAW, src_key + ".png")
        if not os.path.isfile(sp):
            raise SystemExit("gen_skin_views: the source look has no painting %s" % src_key)
        ref = comfy.upload_pil(Image.open(sp).convert("RGB"), comfy.upload_name(key + "_src.png"))
        g.render(key, prompt_of(view, outfit, keep, bg), [front_ref, ref], {"subject": "the same character", "view": None, "subjects_max": 1}, seed + k, tries=1)
        print("gen_skin_views: %s from %s seed %d" % (key, src_key, seed + k))
    print("gen_skin_views: look at %s" % sheet(cid, stills, front_key, keys))


if __name__ == "__main__":
    main()
