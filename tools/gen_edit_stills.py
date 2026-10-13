"""Front paintings as Klein edits of a reference picture, several seeds, picked by eye (pass 53: the Werewolf from
Garry's _REFERENCES/2d/Werewolf.webp in three levels of cartooniness; the same route the Vulture Raider and the HG-C
giant took from scratch scripts). The pick lands in tools/dl/ai_raw_anime as <id>_<stills>_front.png + .json, the
cache gen_art.py reads for a variant whose recipe says "stills": "<stills>", so `gen_art.py --only <id>
--variant=<CODE>` then paints the back and the dead painting from it and walks it.

    python tools/gen_edit_stills.py --id werewolf --stills wwa --ref "_REFERENCES/2d/Werewolf.webp" --seeds 4 \
        --prompt "a hulking werewolf with dark shaggy fur ..." [--screen blue] [--keep "small yellow eyes"] [--first-seed N]
        -> tools/dl/ai_raw_anime/werewolf_wwa_front_c0..c3.png and tools/dl/review/werewolf_wwa_front_cands.png
    python tools/gen_edit_stills.py --id werewolf --stills wwa --pick 2        (installs c2 as werewolf_wwa_front)

--no-style-ref leaves the style anchor out (the reference alone sets the look). The prompt is the creature; the
script adds the view ("full body, front view, standing and facing the viewer, feet fully visible"), the house style
and the screen colour, and runs gen_art's render (vision QA, geometry) once per seed.

Pass 70 (lane LE): --stills is the look's slug only (letters, digits, _: "bdb"), never a picture's path: the Bandit job
put tools/dl/uploads/2d/bandit.png there, the upload name became a path and ComfyUI answered 500 (the picture goes in
--ref). A run paints new candidates every time: the earlier <key>_c<k> files move aside to <key>_c<k>_old<stamp> first
(they were handed back from the cache, so a re-run showed the same fronts), and the seeds are the job's own
(tools/cand_seeds.py: the Level Editor job id and its attempt move them; candidate k a prime past a million from k-1).
--attempt N (or ASSET_JOB_ATTEMPT) is a re-run's number.
"""
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import", "--skip-qa"] if "--skip-qa" in ARGS else ["gen_art.py", "--no-import"]
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import cand_seeds  # noqa: E402
import comfy  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

# the look's slug: what its paintings are cached under (<id>_<slug>_<view>); the Level Editor's job form, its server and
# the recipe editor refuse anything else with the same words
SLUG_RE = re.compile(r"^[A-Za-z0-9_]{1,40}$")
STILLS_HELP = "Stills is a short name for this look's paintings, like bdb; the picture goes in Reference"


def opt(name, default=None):
    for i, a in enumerate(ARGS):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


def sheet(keys, name):
    ims = [Image.open(os.path.join(g.RAW, k + ".png")).convert("RGB") for k in keys]
    W = 400
    out = Image.new("RGB", (W * len(ims), W + 28), (30, 30, 36))
    dr = ImageDraw.Draw(out)
    for i, (k, im) in enumerate(zip(keys, ims)):
        out.paste(im.resize((W, W), Image.LANCZOS), (i * W, 28))
        dr.text((i * W + 6, 6), k, fill=(255, 230, 140))
    d = os.path.join(REPO, "tools", "dl", "review")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name)
    out.save(p)
    return p


def check_slug(stills):
    """SystemExit with the plain words when --stills is not a slug (a path, a file name, spaces)."""
    if not SLUG_RE.match(str(stills or "")):
        raise SystemExit("gen_edit_stills: --stills %r is not a slug. %s (letters, digits and _ only)." % (str(stills), STILLS_HELP))


def retire(key, stamp=None):
    """The earlier candidates of `key` (<key>_c<k>.png/.json in the paintings' cache) moved to <key>_c<k>_old<stamp>, so
    this run paints new ones; returns the new paths."""
    stamp = stamp or time.strftime("%Y%m%d-%H%M%S")
    pat = re.compile(re.escape(key) + r"_c\d+\.(png|json)$")
    moved = []
    for n in sorted(os.listdir(g.RAW)) if os.path.isdir(g.RAW) else []:
        if pat.match(n):
            stem, ext = os.path.splitext(n)
            dst = os.path.join(g.RAW, "%s_old%s%s" % (stem, stamp, ext))
            shutil.move(os.path.join(g.RAW, n), dst)
            moved.append(dst)
    return moved


def candidate_seeds(cid, stills, n, attempt=1, tag="", first=0):
    """The job's first seed (pass 72, "First seed"; 0 = seed_for(id + slug): cand_seeds.start), moved by a re-run's
    attempt (gen_art.LOOK_SEED_STEP each), then cand_seeds.seeds: the job's own move and candidate k CAND_STEP from k-1
    (pass 70; before, every run of a slug painted seed + 1000 k)."""
    base = cand_seeds.start(g.seed_for(cid + stills), first) + g.LOOK_SEED_STEP * max(0, int(attempt or 1) - 1)
    return cand_seeds.seeds(base, n, tag)


def main():
    cid, stills = opt("id"), opt("stills")
    if not cid or not stills:
        raise SystemExit(__doc__)
    check_slug(stills)
    key = "%s_%s_front" % (cid, stills)
    pick = opt("pick")
    if pick is not None:
        for ext in (".png", ".json"):
            shutil.copy(os.path.join(g.RAW, "%s_c%s%s" % (key, pick, ext)), os.path.join(g.RAW, key + ext))
        print("gen_edit_stills: %s_c%s installed as %s" % (key, pick, key))
        return
    ref_path, prompt = opt("ref"), opt("prompt")
    if not ref_path or not prompt:
        raise SystemExit(__doc__)
    n = int(opt("seeds", "4"))
    bg = g.BG_BLUE if opt("screen", "green") == "blue" else g.BG_GREEN
    refs = [] if "--no-style-ref" in ARGS else list(g.ensure_anchor_uploaded())
    src = g.ref_path(ref_path) if hasattr(g, "ref_path") else os.path.join(REPO, ref_path)
    if not src or not os.path.isfile(src):
        raise SystemExit("gen_edit_stills: no reference picture %r (the Reference field: a path under the repo, e.g. "
                         "tools/dl/uploads/2d/x.png)" % str(ref_path))
    ref_img = Image.open(src).convert("RGBA")
    flat = Image.new("RGB", ref_img.size, (255, 255, 255))
    flat.paste(ref_img, mask=ref_img.getchannel("A"))
    look = comfy.upload_pil(flat, comfy.upload_name(cid + "_" + stills + "_ref.png"))
    keep = opt("keep", "")
    style_words = "The first reference image shows the art style only; do not copy its subjects. The second" if refs else "The"
    p = (style_words + " reference image is the creature: redraw this exact creature as a finished 2D anime game creature "
         "illustration of " + prompt + ". Full body, front view, standing and facing the viewer, feet fully visible, the whole "
         "creature inside the picture." + ((" Keep " + keep + ".") if keep else "") + " " + g.STYLE + ". " + bg + ".")
    moved = retire(key)
    if moved:
        print("gen_edit_stills: the earlier candidates moved aside (%d files, *_old<stamp>)" % len(moved))
    seed_list = candidate_seeds(cid, stills, n, cand_seeds.job_attempt(opt("attempt")), cand_seeds.job_tag(), opt("first-seed", "0") or 0)
    keys = []
    for k, s in enumerate(seed_list):
        ck = "%s_c%d" % (key, k)
        g.render(ck, p, refs + [look], {"subject": prompt.split(",")[0], "view": "front", "subjects_max": 1}, s, tries=1)
        print("gen_edit_stills: %s seed %d" % (ck, s))
        keys.append(ck)
    path = sheet(keys, key + "_cands.png")
    print("gen_edit_stills: look at %s, then --pick N" % path)


if __name__ == "__main__":
    main()
